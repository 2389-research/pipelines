# Sprint 002 — Locations, Shifts & Individual Registration (additive)

## Scope
Add four router files: locations + nested stations CRUD, shifts CRUD with `/browse` filter, registrations (signup/cancel/list, auth-required), and volunteer profile self-management. **Purely additive — no edits to any sprint 001 file.** Sprint 001's `main.py` auto-discovers new files in `app/routers/` via `pkgutil`; sprint 001's `models.py` and `schemas.py` already declare every entity and request/response shape this sprint needs.

## Non-goals
- No `models.py` / `schemas.py` / `main.py` / `exceptions.py` / `database.py` / `config.py` edits — those are FROZEN.
- No Group / Waiver / Orientation routes (Sprint 003).
- No QR check-in (Sprint 006).
- No assignment-generation engine (Sprint 007).
- No new fixtures in `conftest.py` (sprint 001 provides everything this sprint needs).

## Dependencies (sprint 001 contracts this sprint imports — none get redefined here)

- **Models**: `Volunteer`, `Location`, `Station`, `Shift`, `Registration`, `RegistrationStatus`, `EnvironmentType`, `LaborCondition` from `app.models`.
- **Schemas**: `LocationCreate`, `LocationRead`, `StationCreate`, `StationRead`, `ShiftCreate`, `ShiftRead`, `RegistrationCreate`, `RegistrationRead`, `VolunteerRead`, `VolunteerUpdate` from `app.schemas`.
- **DB / auth**: `get_db` from `app.database`, `get_current_volunteer` from `app.dependencies`.
- **Errors**: `AppError`, `NOT_FOUND`, `SHIFT_FULL`, `DUPLICATE_REGISTRATION`, `FORBIDDEN` from `app.exceptions`.
- **Test fixtures**: `client`, `db_session`, `test_volunteer`, `auth_headers`, `test_location`, `test_station`, `test_shift` — already in `conftest.py`.

## Conventions (inherited from Sprint 001 — listed here for tight feedback)
- Router files declare `router = APIRouter(prefix="/<resource>", tags=["<resource>"])`. Sprint 001's `main.py` auto-discovers via `pkgutil`.
- Routers raise `AppError(status_code, detail, error_code)` — never raw `HTTPException`, never custom JSONResponse.
- All route handlers are `async def`. All DB queries `await`.
- Tests are `async def` (pytest-asyncio `mode=auto`). **Do NOT add `@pytest.mark.asyncio` decorators.**
- Tests take fixtures (`client`, `auth_headers`, `test_shift`, etc.) as **function parameters**. Never construct `AsyncClient`, engines, or sessions inside test bodies.
- Authenticated requests pass `headers=auth_headers` to the client method. Example: `await client.post("/registrations", json={...}, headers=auth_headers)`.
- Imports are full Python statements, never bare module names. For class-vs-module collisions (`date`, `time`, `datetime`), use `from X import Y` form.

## Tricky semantics (load-bearing — read before writing routes)

1. **Cancelled registrations do NOT count toward shift capacity.** Capacity check filters `status != RegistrationStatus.cancelled`. Same filter for duplicate detection.
2. **Duplicate-registration check is on `(volunteer_id, shift_id)` pairs that are NOT cancelled.** A volunteer who cancels a registration may register again — that's not a duplicate.
3. **Cancellation is soft.** `DELETE /registrations/{id}` sets `status = RegistrationStatus.cancelled` and returns 204; the row remains.
4. **Ownership check on cancel.** A volunteer cannot cancel another volunteer's registration. If `registration.volunteer_id != volunteer.id`, return `AppError(404, NOT_FOUND)` (not 403, to avoid leaking the existence of others' registrations).
5. **`PATCH /volunteers/me` is partial.** Only update fields that are explicitly set in the request (i.e., not `None`). Use `req.model_dump(exclude_unset=True)` to detect which fields the client actually sent.
6. **`/shifts/browse` includes `registered_count`.** Each `ShiftRead` returned must populate `registered_count` from `count(Registration where shift_id=... AND status != cancelled)`. The default `registered_count=0` in the schema only applies when not set explicitly.

## Data contract (no new types — referenced from sprint 001)

This sprint adds NO new models, NO new schemas, NO new enums. All shapes are imported from sprint 001's frozen `app.models` and `app.schemas`.

## API contract

All routes mounted via the auto-discovery in `main.py` (sprint 001). Each router declares its own `prefix` and `tags`.

**Path and query parameter types — use these exact Python annotations in route handler signatures (do NOT default to `str`):**
- `location_id`, `shift_id`, `registration_id`, `station_id` — all are `uuid.UUID` (path params).
- `location_id` (query, on `/shifts/browse`) — `uuid.UUID | None = None`.
- `on_date` (query, on `/shifts/browse`) — `date | None = None`.
- Any other UUID-shaped param — `uuid.UUID`.

If you annotate as `str` instead of `uuid.UUID`, FastAPI does not parse-and-validate the UUID, and SQLAlchemy's UUID column bind processor crashes with `AttributeError: 'str' object has no attribute 'hex'`.

**Path-string convention (load-bearing):** Use the **empty string `""`** for collection-level routes under a router prefix — NOT `"/"`. Example: `@router.post("", ...)` (correct), not `@router.post("/", ...)` (wrong). With the prefix `/locations`, the empty string makes the route URL exactly `/locations`; the trailing-slash form makes it `/locations/`, and tests calling `/locations` get a 307 redirect that AsyncClient does not follow by default → tests assert 200, observe 307, fail.

**Route declaration order (load-bearing):** Within a single router, declare more-specific paths BEFORE parameterized ones that share a prefix. FastAPI matches routes in declaration order — `@router.get("/{shift_id}")` declared before `@router.get("/browse")` will match `/shifts/browse` against `/{shift_id}` (with `shift_id="browse"`), then fail UUID parsing with 422. Required order in `shifts.py`: list/create at `""`, then `/browse`, then `/{shift_id}`. Same pattern for any router with both static and parameterized routes.

| Method | Path | Auth | Request | Response (status) | Errors |
|---|---|---|---|---|---|
| POST | `/locations` | none | `LocationCreate` | `LocationRead` (201) | — |
| GET | `/locations` | none | — | `list[LocationRead]` (200) | — |
| GET | `/locations/{location_id}` | none | — | `LocationRead` (200) | 404 `NOT_FOUND` |
| POST | `/locations/{location_id}/stations` | none | `StationCreate` | `StationRead` (201) | 404 `NOT_FOUND` (location missing) |
| GET | `/locations/{location_id}/stations` | none | — | `list[StationRead]` (200) | 404 `NOT_FOUND` (location missing) |
| POST | `/shifts` | none | `ShiftCreate` | `ShiftRead` (201) | — |
| GET | `/shifts` | none | — | `list[ShiftRead]` (200) | — |
| GET | `/shifts/browse` | none | query: `location_id?`, `on_date?` | `list[ShiftRead]` with `registered_count` populated (200) | — |
| GET | `/shifts/{shift_id}` | none | — | `ShiftRead` (200) | 404 `NOT_FOUND` |

**Important — declaration order in `shifts.py` MUST match the table above** (POST `""`, GET `""`, GET `/browse`, GET `/{shift_id}`). FastAPI matches routes in declaration order; if `/{shift_id}` is declared before `/browse`, every request to `/shifts/browse` matches `/{shift_id}` with `shift_id="browse"` and fails UUID parsing with 422.
| POST | `/registrations` | required | `RegistrationCreate` | `RegistrationRead` (201) | 404 `NOT_FOUND` (shift missing), 409 `DUPLICATE_REGISTRATION`, 409 `SHIFT_FULL` |
| DELETE | `/registrations/{registration_id}` | required | — | (204, no body) | 404 `NOT_FOUND` (missing or not owned) |
| GET | `/registrations/me` | required | — | `list[RegistrationRead]` (200) | — |
| GET | `/volunteers/me` | required | — | `VolunteerRead` (200) | 401 `UNAUTHORIZED` (no/bad token) |
| PATCH | `/volunteers/me` | required | `VolunteerUpdate` | `VolunteerRead` (200) | 401 `UNAUTHORIZED` |

## Algorithm

### `POST /registrations` — `create_registration`
1. Look up `Shift` by `req.shift_id`. If none → `raise AppError(404, "Shift not found", NOT_FOUND)`.
2. Look up duplicate `Registration` where `volunteer_id == volunteer.id AND shift_id == req.shift_id AND status != RegistrationStatus.cancelled`. If exists → `raise AppError(409, "Already registered for this shift", DUPLICATE_REGISTRATION)`.
3. Count active registrations for the shift: `select(func.count(Registration.id)).where(Registration.shift_id == req.shift_id, Registration.status != RegistrationStatus.cancelled)`. If `count >= shift.max_volunteers` → `raise AppError(409, "Shift is full", SHIFT_FULL)`.
4. Insert `Registration(volunteer_id=volunteer.id, shift_id=req.shift_id)` (status defaults to `registered`); `await db.commit(); await db.refresh(reg)`.
5. Return the registration.

### `DELETE /registrations/{registration_id}` — `cancel_registration`
1. Look up `Registration` by id. If none, OR if `registration.volunteer_id != volunteer.id` → `raise AppError(404, "Registration not found", NOT_FOUND)`. (Use 404, not 403, to avoid leaking the existence of others' rows.)
2. Set `registration.status = RegistrationStatus.cancelled`; `await db.commit()`.
3. Return `None` (FastAPI emits 204 because the route declares `status_code=204`).

### `GET /registrations/me` — `my_registrations`
1. Query `Registration` where `volunteer_id == volunteer.id`, ordered by `created_at desc`.
2. Return the list.

### `GET /shifts/browse` — `browse_shifts(location_id?, on_date?)`

**Declaration order: this `@router.get("/browse")` MUST be declared BEFORE `@router.get("/{shift_id}")` in `shifts.py` so that `/shifts/browse` doesn't match the parameterized route first.**

1. Build `stmt = select(Shift)`. If `location_id` is provided, `stmt = stmt.where(Shift.location_id == location_id)`. If `on_date` is provided, `stmt = stmt.where(Shift.date == on_date)`.
2. Execute `stmt`; collect shifts.
3. For each shift, compute `registered_count = count(Registration where shift_id == shift.id AND status != cancelled)`.
4. Construct each `ShiftRead` with **EXACTLY these fields and no others**: `id`, `location_id`, `title`, `description`, `date`, `start_time`, `end_time`, `max_volunteers`, `registered_count`. **Do NOT pass any other field** (`Shift` does not have a `station_id`, `volunteer_id`, `assigned_volunteers`, or any other field — only the ones listed in sprint 001's data contract). Do NOT use `ShiftRead.model_validate(shift)` since that won't compute the derived `registered_count`.

### `GET /shifts/{shift_id}` — `get_shift`

**Declared AFTER `/browse` (see above).**

1. Look up shift by id. If none → `raise AppError(404, "Shift not found", NOT_FOUND)`.
2. Return shift (FastAPI serializes via `ShiftRead`'s `from_attributes=True`; `registered_count` defaults to 0 from the schema since this endpoint doesn't compute it).

### `POST /locations` / `GET /locations` / `GET /locations/{id}` / `POST /locations/{id}/stations` / `GET /locations/{id}/stations`
Standard CRUD: insert + commit + refresh on creates; select on reads. For the nested `/stations` endpoints, look up the parent location first; if missing, `raise AppError(404, "Location not found", NOT_FOUND)`.

### `GET /volunteers/me`
Return the `volunteer` parameter (resolved by `Depends(get_current_volunteer)`) directly; FastAPI serializes via `VolunteerRead`.

### `PATCH /volunteers/me` — `update_my_profile`
1. `update_data = req.model_dump(exclude_unset=True)` — keeps only fields the client actually sent.
2. For each `field, value` in `update_data.items()`: `setattr(volunteer, field, value)`.
3. `await db.commit(); await db.refresh(volunteer)`.
4. Return the volunteer.

## Test contract

All test functions are `async def`. None have decorators. All take `client` from conftest as a parameter; routes that require auth additionally take `auth_headers`. Multi-volunteer scenarios construct the second volunteer via `db_session` (the `test_volunteer` fixture provides only one).

### `tests/test_locations.py` (7 tests)

| Test | Action | Asserts |
|---|---|---|
| `test_create_location_returns_201(client)` | POST `/locations` `{"name": "Main", "address": "1 Test St"}` | 201, body has `id`, `name == "Main"` |
| `test_list_locations_empty(client)` | GET `/locations` | 200, `body == []` |
| `test_list_locations_nonempty(client, test_location)` | GET `/locations` | 200, `len(body) == 1`, body[0]["id"] == str(test_location.id) |
| `test_get_location_by_id(client, test_location)` | GET `/locations/{test_location.id}` | 200, `body["name"] == test_location.name` |
| `test_get_location_not_found_404(client)` | GET `/locations/{uuid.uuid4()}` | 404, `error_code == "NOT_FOUND"` |
| `test_create_station_for_location(client, test_location)` | POST `/locations/{test_location.id}/stations` `{"name":"Sorting","max_capacity":10,"environment_type":"indoor","labor_condition":"standing"}` | 201, body has `id`, `location_id == str(test_location.id)` |
| `test_list_stations_for_location(client, test_station)` | GET `/locations/{test_station.location_id}/stations` | 200, `len(body) >= 1`, one entry has `id == str(test_station.id)` |

### `tests/test_shifts.py` (7 tests)

| Test | Action | Asserts |
|---|---|---|
| `test_create_shift_returns_201(client, test_location)` | POST `/shifts` with `location_id=test_location.id`, valid title/date/times/max_volunteers | 201, body has `id`, `location_id == str(test_location.id)`, `registered_count == 0` |
| `test_list_all_shifts(client, test_shift)` | GET `/shifts` | 200, `len(body) >= 1`, one entry has `id == str(test_shift.id)` |
| `test_get_shift_by_id(client, test_shift)` | GET `/shifts/{test_shift.id}` | 200, `body["title"] == test_shift.title` |
| `test_get_shift_not_found_404(client)` | GET `/shifts/{uuid.uuid4()}` | 404, `error_code == "NOT_FOUND"` |
| `test_browse_filter_by_location(client, test_location, test_shift)` | GET `/shifts/browse?location_id={test_location.id}` | 200, all returned shifts have `location_id == str(test_location.id)` |
| `test_browse_filter_by_date(client, test_shift)` | GET `/shifts/browse?on_date={test_shift.date.isoformat()}` | 200, all returned shifts have `date == test_shift.date.isoformat()` |
| `test_browse_includes_registered_count(client, test_shift, test_volunteer, db_session)` | Insert `Registration(volunteer_id=test_volunteer.id, shift_id=test_shift.id)` via `db_session`, commit; then GET `/shifts/browse` | 200, the entry for `test_shift.id` has `registered_count == 1` |

### `tests/test_registrations.py` (8 tests)

| Test | Action | Asserts |
|---|---|---|
| `test_register_for_shift_returns_201(client, auth_headers, test_shift)` | POST `/registrations` `{"shift_id": str(test_shift.id)}`, headers=auth_headers | 201, body has `id`, `shift_id == str(test_shift.id)`, `status == "registered"` |
| `test_register_nonexistent_shift_returns_404(client, auth_headers)` | POST `/registrations` `{"shift_id": str(uuid.uuid4())}`, headers=auth_headers | 404, `error_code == "NOT_FOUND"` |
| `test_register_duplicate_returns_409(client, auth_headers, test_shift)` | Register once successfully; then POST `/registrations` again with the same shift_id | 409, `error_code == "DUPLICATE_REGISTRATION"` |
| `test_register_full_shift_returns_409_capacity_full(client, auth_headers, test_shift, db_session)` | Insert `test_shift.max_volunteers` `Registration` rows directly via `db_session` (different volunteer_ids), commit; then attempt to register the auth user | 409, `error_code == "SHIFT_FULL"` |
| `test_list_my_registrations(client, auth_headers, test_shift)` | Register; then GET `/registrations/me`, headers=auth_headers | 200, `len(body) == 1`, body[0]["shift_id"] == str(test_shift.id) |
| `test_cancel_registration_returns_204(client, auth_headers, test_shift)` | Register; then DELETE `/registrations/{registration_id}`, headers=auth_headers | 204 (empty body) |
| `test_cancel_sets_status_cancelled(client, auth_headers, test_shift, db_session)` | Register; cancel; query the row via `db_session` | `registration.status == RegistrationStatus.cancelled` |
| `test_cancelled_registration_does_not_count_toward_capacity(client, auth_headers, test_shift, db_session)` | Insert `test_shift.max_volunteers` `Registration` rows then cancel one; attempt to register | 201 (capacity has room because cancelled doesn't count) |

### `tests/test_volunteers.py` (4 tests)

| Test | Action | Asserts |
|---|---|---|
| `test_get_my_profile_returns_200(client, auth_headers, test_volunteer)` | GET `/volunteers/me`, headers=auth_headers | 200, `body["id"] == str(test_volunteer.id)` |
| `test_get_profile_unauthorized_returns_401(client)` | GET `/volunteers/me` (no headers) | 401, `error_code == "UNAUTHORIZED"` |
| `test_update_first_last_name(client, auth_headers, test_volunteer)` | PATCH `/volunteers/me` `{"first_name":"NewFirst","last_name":"NewLast"}`, headers=auth_headers | 200, `body["first_name"] == "NewFirst"`, `body["last_name"] == "NewLast"` |
| `test_partial_update_ignores_none_fields(client, auth_headers, test_volunteer)` | PATCH `/volunteers/me` `{"first_name":"OnlyFirst"}`, headers=auth_headers | 200, `body["first_name"] == "OnlyFirst"`, `body["last_name"] == test_volunteer.last_name` (unchanged) |

## New files
- `backend/app/routers/locations.py` — `router = APIRouter(prefix="/locations", tags=["locations"])` and the 5 location/station endpoints per "API contract" + "Algorithm" sections. Imports (use these EXACT statements): `import uuid`, `from fastapi import APIRouter, Depends`, `from sqlalchemy import select`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.database import get_db`, `from app.exceptions import AppError, NOT_FOUND`, `from app.models import Location, Station`, `from app.schemas import LocationCreate, LocationRead, StationCreate, StationRead`.
- `backend/app/routers/shifts.py` — `router = APIRouter(prefix="/shifts", tags=["shifts"])` and the 4 shift endpoints (including `/browse` with the `registered_count` algorithm). Imports: `import uuid`, `from datetime import date`, `from fastapi import APIRouter, Depends`, `from sqlalchemy import select, func`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.database import get_db`, `from app.exceptions import AppError, NOT_FOUND`, `from app.models import Shift, Registration, RegistrationStatus`, `from app.schemas import ShiftCreate, ShiftRead`.
- `backend/app/routers/registrations.py` — `router = APIRouter(prefix="/registrations", tags=["registrations"])` and the 3 auth-required registration endpoints per "Algorithm" section. Imports: `import uuid`, `from fastapi import APIRouter, Depends`, `from sqlalchemy import select, func`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.database import get_db`, `from app.dependencies import get_current_volunteer`, `from app.exceptions import AppError, NOT_FOUND, SHIFT_FULL, DUPLICATE_REGISTRATION`, `from app.models import Volunteer, Shift, Registration, RegistrationStatus`, `from app.schemas import RegistrationCreate, RegistrationRead`.
- `backend/app/routers/volunteers.py` — `router = APIRouter(prefix="/volunteers", tags=["volunteers"])` and the 2 profile endpoints. Imports: `from fastapi import APIRouter, Depends`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.database import get_db`, `from app.dependencies import get_current_volunteer`, `from app.models import Volunteer`, `from app.schemas import VolunteerRead, VolunteerUpdate`.
- `backend/tests/test_locations.py` — 7 tests per "Test contract → test_locations.py" table. Imports: `import uuid`, `from httpx import AsyncClient`. Uses `client`, `test_location`, `test_station` fixtures.
- `backend/tests/test_shifts.py` — 7 tests per "Test contract → test_shifts.py" table. Imports: `import uuid`, `from datetime import date, time, timedelta`, `from httpx import AsyncClient`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.models import Registration, RegistrationStatus`. Uses `client`, `test_location`, `test_shift`, `test_volunteer`, `db_session` fixtures.
- `backend/tests/test_registrations.py` — 8 tests per "Test contract → test_registrations.py" table. Imports: `import uuid`, `from httpx import AsyncClient`, `from sqlalchemy import select`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.models import Volunteer, Registration, RegistrationStatus`. Uses `client`, `auth_headers`, `test_shift`, `db_session` fixtures.
- `backend/tests/test_volunteers.py` — 4 tests per "Test contract → test_volunteers.py" table. Imports: `from httpx import AsyncClient`. Uses `client`, `auth_headers`, `test_volunteer` fixtures.

## Modified files
(none — Sprint 001's `main.py` auto-discovers new router files via `pkgutil`; no schema, model, or main.py edits required.)

## Rules
- All new files go under `backend/`. NO modifications to any sprint 001 file.
- Routers expose their `APIRouter` instance as the module-level name `router`. Without this, `main.py`'s `pkgutil.iter_modules(...)` discovery skips them silently.
- Routers use `prefix="/<resource>"` on the `APIRouter()` constructor — paths inside the router decorators are relative.
- Imports use `from app.X import Y` form throughout. No relative imports.
- Imports are full Python statements, never bare module names. For class-vs-module collisions (`date`, `time`, `datetime`), use `from X import Y` form.
- Tests take fixtures (`client`, `auth_headers`, `test_shift`, etc.) as **function parameters** — never construct `AsyncClient`, engines, or sessions inside test bodies. `conftest.py` is the single point of test setup.
- All test functions are `async def`. Do NOT add `@pytest.mark.asyncio` decorators (`asyncio_mode = "auto"` in `pyproject.toml` handles them).
- Authenticated requests pass `headers=auth_headers` to the client method (the `auth_headers` fixture returns `{"Authorization": f"Bearer {token}"}`).
- `RegistrationStatus.cancelled` records do NOT count toward shift capacity OR toward duplicate-registration detection. Use `Registration.status != RegistrationStatus.cancelled` in capacity and duplicate filters.
- Cancellation is soft (set status, don't delete). The DELETE endpoint returns 204 with no body.
- Ownership check on cancel: if the registration isn't owned by the auth user, raise `AppError(404, NOT_FOUND)` (not 403). This avoids leaking the existence of others' registrations.
- `PATCH /volunteers/me` is partial — use `req.model_dump(exclude_unset=True)` to detect which fields the client sent, and only update those.
- `/shifts/browse` constructs `ShiftRead` instances explicitly (not via `from_attributes`) so `registered_count` can be populated per-shift.
- **Route handler path/query parameters must be typed as the actual Python type (`uuid.UUID`, `date`, etc.), not as `str`.** FastAPI uses the annotation to parse and validate the incoming value; an `str` annotation passes the raw string into the database layer where UUID columns reject it.
- **Pydantic Read schemas have EXACTLY the fields declared in sprint 001's data contract.** Do NOT invent fields based on what "ought to" be there (e.g., `Shift` has no `station_id`, `volunteer_id`, or `assignee` field; that relationship lives on `Assignment`). When constructing a Read schema explicitly, pass only the fields that the schema declares.
- **Collection routes use empty-string path `""`, not `"/"`.** Trailing-slash form causes 307 redirects when tests call without the slash. (`@router.post("", ...)` correct; `@router.post("/", ...)` wrong.)
- **Within a router, declare static-path routes BEFORE parameterized routes that share their prefix.** FastAPI matches in declaration order; reverse order makes static paths unreachable.
- **Tests parse string UUIDs from JSON responses with `uuid.UUID(...)` before using them in ORM queries.** `response.json()["id"]` is a string; SQLAlchemy's UUID column bind processor expects `uuid.UUID` instances and crashes with `AttributeError: 'str' object has no attribute 'hex'` on raw strings. Pattern: `reg_id = uuid.UUID(response.json()["id"]); result = await db_session.execute(select(Registration).where(Registration.id == reg_id))`.
- **Tests serialize `date`, `time`, `datetime`, and `uuid.UUID` values to strings before passing them as JSON request bodies.** httpx's `json=` argument uses Python's stdlib `json.dumps`, which raises `TypeError: Object of type date is not JSON serializable` on raw `date`/`time`/`datetime` objects. Pattern: `json={"date": date.today().isoformat(), "start_time": time(9, 0).isoformat(), "location_id": str(test_location.id), ...}`. Stringify everything that isn't a primitive (str/int/float/bool/None/list/dict).

## DoD
- [ ] `cd backend && uv run pytest tests/test_locations.py -v` passes (7 tests).
- [ ] `cd backend && uv run pytest tests/test_shifts.py -v` passes (7 tests).
- [ ] `cd backend && uv run pytest tests/test_registrations.py -v` passes (8 tests).
- [ ] `cd backend && uv run pytest tests/test_volunteers.py -v` passes (4 tests).
- [ ] `cd backend && uv run pytest -v` cumulative ≥ 47 tests passing (21 from sprint 001 + 26 new = 47).
- [ ] `cd backend && uv run ruff check app/ tests/` exits 0.
- [ ] None of sprint 001's foundation files (`main.py`, `models.py`, `schemas.py`, `exceptions.py`, `database.py`, `config.py`) are modified by this sprint.

## Validation
```bash
cd backend
uv run pytest -v --tb=short
uv run ruff check app/ tests/
```
