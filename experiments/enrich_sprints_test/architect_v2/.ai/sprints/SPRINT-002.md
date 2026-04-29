# Sprint 002 — Locations, Shifts & Individual Registration (enriched spec, additive)

## Scope
Add router files for locations/stations CRUD, shifts CRUD with a browse endpoint, registrations (signup/cancel/list), and volunteer profile self-management. **All models, schemas, exceptions, and main.py are FROZEN from sprint 001 — this sprint only adds new router files and tests, no edits to foundation files.**

## Non-goals
- No models.py / schemas.py edits — the schemas needed (`LocationCreate`, `ShiftCreate`, `Registration*`, etc.) were defined in sprint 001
- No main.py edits — sprint 001's pkgutil auto-discovery picks up new router files automatically
- No Group / Waiver / Orientation routes (Sprint 003)
- No QR check-in (Sprint 006)
- No assignment generation (Sprint 007)

## Dependencies
- Sprint 001: `app.models` exposes `Volunteer, Location, Station, Shift, Registration, RegistrationStatus, EnvironmentType, LaborCondition`
- Sprint 001: `app.schemas` exposes `LocationCreate, LocationRead, StationCreate, StationRead, ShiftCreate, ShiftRead, RegistrationCreate, RegistrationRead, VolunteerRead, VolunteerUpdate`
- Sprint 001: `app.dependencies.get_current_volunteer`, `app.database.get_db`
- Sprint 001: `app.exceptions.AppError, NOT_FOUND, SHIFT_FULL, DUPLICATE_REGISTRATION, FORBIDDEN`
- Sprint 001: `app.main` auto-discovers routers via pkgutil; new files in `app/routers/` are picked up at startup
- Sprint 001: `tests/conftest.py` provides `client, db_session, test_volunteer, auth_headers, test_location, test_station, test_shift` fixtures

## Python/runtime conventions (inherited from Sprint 001)
All conventions inherited. No new ones.

## File structure

```
backend/app/routers/locations.py        — POST/GET/GET/{id}/PATCH /locations + nested /locations/{id}/stations
backend/app/routers/shifts.py           — POST/GET/GET/{id}/PATCH /shifts + GET /shifts/browse
backend/app/routers/registrations.py    — POST /registrations, DELETE /registrations/{id}, GET /registrations/me
backend/app/routers/volunteers.py       — GET /volunteers/me, PATCH /volunteers/me
backend/tests/test_locations.py         — Location + Station CRUD tests
backend/tests/test_shifts.py            — Shift CRUD + browse filter tests
backend/tests/test_registrations.py     — register/cancel/list tests + capacity + duplicate
backend/tests/test_volunteers.py        — profile read/update + unauth tests
```

## Interface contract

### `backend/app/routers/locations.py`
```python
router = APIRouter(prefix="/locations", tags=["locations"])

@router.post("", response_model=LocationRead, status_code=201)
async def create_location(req: LocationCreate, db: AsyncSession = Depends(get_db)) -> LocationRead: ...

@router.get("", response_model=list[LocationRead])
async def list_locations(db: AsyncSession = Depends(get_db)) -> list[LocationRead]: ...

@router.get("/{location_id}", response_model=LocationRead)
async def get_location(location_id: uuid.UUID, db: AsyncSession = Depends(get_db)) -> LocationRead: ...
# Raises AppError(404, NOT_FOUND) if missing.

@router.post("/{location_id}/stations", response_model=StationRead, status_code=201)
async def create_station(location_id: uuid.UUID, req: StationCreate, db: AsyncSession = Depends(get_db)) -> StationRead: ...

@router.get("/{location_id}/stations", response_model=list[StationRead])
async def list_stations(location_id: uuid.UUID, db: AsyncSession = Depends(get_db)) -> list[StationRead]: ...
```

### `backend/app/routers/shifts.py`
```python
router = APIRouter(prefix="/shifts", tags=["shifts"])

@router.post("", response_model=ShiftRead, status_code=201)
async def create_shift(req: ShiftCreate, db: AsyncSession = Depends(get_db)) -> ShiftRead: ...

@router.get("", response_model=list[ShiftRead])
async def list_shifts(db: AsyncSession = Depends(get_db)) -> list[ShiftRead]: ...

@router.get("/browse", response_model=list[ShiftRead])
async def browse_shifts(
    location_id: uuid.UUID | None = None,
    on_date: date | None = None,
    db: AsyncSession = Depends(get_db),
) -> list[ShiftRead]:
    """Filter by location and/or date. Each result includes registered_count derived from active registrations."""

@router.get("/{shift_id}", response_model=ShiftRead)
async def get_shift(shift_id: uuid.UUID, db: AsyncSession = Depends(get_db)) -> ShiftRead: ...
# AppError(404) if missing.
```

### `backend/app/routers/registrations.py`
```python
router = APIRouter(prefix="/registrations", tags=["registrations"])

@router.post("", response_model=RegistrationRead, status_code=201)
async def create_registration(
    req: RegistrationCreate,
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> RegistrationRead:
    """Validates: shift exists (404), shift not full (409 SHIFT_FULL), no duplicate active registration for this volunteer+shift (409 DUPLICATE_REGISTRATION). Cancelled registrations DON'T count toward capacity."""

@router.delete("/{registration_id}", status_code=204)
async def cancel_registration(
    registration_id: uuid.UUID,
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Sets status=cancelled. AppError(404) if missing or volunteer doesn't own it."""

@router.get("/me", response_model=list[RegistrationRead])
async def my_registrations(
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> list[RegistrationRead]: ...
```

### `backend/app/routers/volunteers.py`
```python
router = APIRouter(prefix="/volunteers", tags=["volunteers"])

@router.get("/me", response_model=VolunteerRead)
async def get_my_profile(volunteer: Volunteer = Depends(get_current_volunteer)) -> VolunteerRead: ...

@router.patch("/me", response_model=VolunteerRead)
async def update_my_profile(
    req: VolunteerUpdate,
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> VolunteerRead:
    """Updates only fields explicitly set in req (None means skip)."""
```

## Imports per file

**`backend/app/routers/locations.py`**
```python
import uuid
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.exceptions import AppError, NOT_FOUND
from app.models import Location, Station
from app.schemas import LocationCreate, LocationRead, StationCreate, StationRead
```

**`backend/app/routers/shifts.py`**
```python
import uuid
from datetime import date
from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.exceptions import AppError, NOT_FOUND
from app.models import Shift, Registration, RegistrationStatus
from app.schemas import ShiftCreate, ShiftRead
```

**`backend/app/routers/registrations.py`**
```python
import uuid
from fastapi import APIRouter, Depends
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.dependencies import get_current_volunteer
from app.exceptions import AppError, NOT_FOUND, SHIFT_FULL, DUPLICATE_REGISTRATION, FORBIDDEN
from app.models import Volunteer, Shift, Registration, RegistrationStatus
from app.schemas import RegistrationCreate, RegistrationRead
```

**`backend/app/routers/volunteers.py`**
```python
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.dependencies import get_current_volunteer
from app.models import Volunteer
from app.schemas import VolunteerRead, VolunteerUpdate
```

**`backend/tests/test_locations.py`** / **`test_shifts.py`** / **`test_registrations.py`** / **`test_volunteers.py`**
```python
import pytest
import uuid
from datetime import date, time, timedelta
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import (
    Volunteer, Location, Station, Shift, Registration,
    RegistrationStatus, EnvironmentType, LaborCondition,
)
```

## Algorithm notes

### `backend/app/routers/registrations.py — create_registration` (capacity + duplicate detection)
```python
@router.post("", response_model=RegistrationRead, status_code=201)
async def create_registration(req, volunteer, db):
    # 1. Verify shift exists
    shift = (await db.execute(select(Shift).where(Shift.id == req.shift_id))).scalar_one_or_none()
    if shift is None:
        raise AppError(404, "Shift not found", NOT_FOUND)

    # 2. Check duplicate (any non-cancelled registration for this volunteer+shift)
    dup = (await db.execute(
        select(Registration).where(
            Registration.volunteer_id == volunteer.id,
            Registration.shift_id == req.shift_id,
            Registration.status != RegistrationStatus.cancelled,
        )
    )).scalar_one_or_none()
    if dup is not None:
        raise AppError(409, "Already registered for this shift", DUPLICATE_REGISTRATION)

    # 3. Check capacity (cancelled registrations don't count)
    count = (await db.execute(
        select(func.count(Registration.id)).where(
            Registration.shift_id == req.shift_id,
            Registration.status != RegistrationStatus.cancelled,
        )
    )).scalar_one()
    if count >= shift.max_volunteers:
        raise AppError(409, "Shift is full", SHIFT_FULL)

    reg = Registration(volunteer_id=volunteer.id, shift_id=req.shift_id)
    db.add(reg)
    await db.commit()
    await db.refresh(reg)
    return reg
```

### `backend/app/routers/shifts.py — browse_shifts` (filter + registered_count)
```python
@router.get("/browse", response_model=list[ShiftRead])
async def browse_shifts(location_id=None, on_date=None, db=Depends(get_db)):
    stmt = select(Shift)
    if location_id is not None:
        stmt = stmt.where(Shift.location_id == location_id)
    if on_date is not None:
        stmt = stmt.where(Shift.date == on_date)
    shifts = (await db.execute(stmt)).scalars().all()
    out = []
    for s in shifts:
        c = (await db.execute(
            select(func.count(Registration.id)).where(
                Registration.shift_id == s.id,
                Registration.status != RegistrationStatus.cancelled,
            )
        )).scalar_one()
        out.append(ShiftRead(
            id=s.id, location_id=s.location_id, title=s.title, description=s.description,
            date=s.date, start_time=s.start_time, end_time=s.end_time,
            max_volunteers=s.max_volunteers, registered_count=c,
        ))
    return out
```

## Test plan

### `backend/tests/test_locations.py`
```python
async def test_create_location_returns_201(client, auth_headers): ...  # POST /locations -> 201
async def test_list_locations_empty(client): ...                        # GET /locations -> []
async def test_list_locations_nonempty(client, test_location): ...      # GET /locations -> [test_location]
async def test_get_location_by_id(client, test_location): ...           # GET /locations/{id}
async def test_get_location_not_found_404(client): ...                  # GET random uuid -> 404
async def test_create_station_for_location(client, test_location): ...  # POST /locations/{id}/stations
async def test_list_stations_for_location(client, test_station): ...    # GET /locations/{id}/stations
```

### `backend/tests/test_shifts.py`
```python
async def test_create_shift_returns_201(client, test_location): ...
async def test_list_all_shifts(client, test_shift): ...
async def test_get_shift_by_id(client, test_shift): ...
async def test_get_shift_not_found_404(client): ...
async def test_browse_filter_by_location(client, test_location, test_shift): ...
async def test_browse_filter_by_date(client, test_shift): ...
async def test_browse_includes_registered_count(client, test_shift, test_volunteer, db_session): ...
```

### `backend/tests/test_registrations.py`
```python
async def test_register_for_shift_returns_201(client, auth_headers, test_shift): ...
async def test_register_nonexistent_shift_returns_404(client, auth_headers): ...
async def test_register_duplicate_returns_409(client, auth_headers, test_shift): ...
async def test_register_full_shift_returns_409_capacity_full(client, auth_headers, test_shift, db_session): ...
async def test_list_my_registrations(client, auth_headers, test_shift): ...
async def test_cancel_registration_returns_204(client, auth_headers, test_shift): ...
async def test_cancel_sets_status_cancelled(client, auth_headers, test_shift, db_session): ...
async def test_cancelled_registration_does_not_count_toward_capacity(client, auth_headers, test_shift, db_session): ...
```

### `backend/tests/test_volunteers.py`
```python
async def test_get_my_profile_returns_200(client, auth_headers): ...
async def test_get_profile_unauthorized_returns_401(client): ...
async def test_update_first_last_name(client, auth_headers): ...
async def test_partial_update_ignores_none_fields(client, auth_headers): ...
```

## Rules
- All new files go under `backend/`. NO modifications to any sprint 001 file.
- Routers use `prefix=` on the `APIRouter()` they construct so main.py's auto-discovery picks them up correctly.
- Imports use `from app.X` form throughout.
- Test files use the `client` fixture (pre-configured with sprint 001's app + DB override) and the `auth_headers` fixture for authenticated requests.
- `RegistrationStatus.cancelled` records do NOT count toward shift capacity.

## New files
- `backend/app/routers/locations.py` — `router` exporting Location/Station CRUD endpoints
- `backend/app/routers/shifts.py` — `router` exporting Shift CRUD + browse endpoint with registered_count
- `backend/app/routers/registrations.py` — `router` exporting registration create/cancel/list (auth-required)
- `backend/app/routers/volunteers.py` — `router` exporting profile self-read/self-update
- `backend/tests/test_locations.py` — Location + Station CRUD test cases
- `backend/tests/test_shifts.py` — Shift CRUD + browse filter test cases
- `backend/tests/test_registrations.py` — Registration tests including capacity + duplicate
- `backend/tests/test_volunteers.py` — Volunteer profile self-management tests

## Modified files
(none — Sprint 001's main.py auto-discovers new router files via pkgutil; no schema or model edits required.)

## Expected Artifacts
- `backend/app/routers/locations.py`
- `backend/app/routers/shifts.py`
- `backend/app/routers/registrations.py`
- `backend/app/routers/volunteers.py`
- `backend/tests/test_locations.py`
- `backend/tests/test_shifts.py`
- `backend/tests/test_registrations.py`
- `backend/tests/test_volunteers.py`

## DoD
- [ ] `cd backend && uv run pytest tests/test_locations.py -v` passes
- [ ] `cd backend && uv run pytest tests/test_shifts.py -v` passes
- [ ] `cd backend && uv run pytest tests/test_registrations.py -v` passes
- [ ] `cd backend && uv run pytest tests/test_volunteers.py -v` passes
- [ ] `cd backend && uv run pytest -v` passes (sprint 001's tests still green)
- [ ] `cd backend && uv run ruff check app/ tests/` clean

## Validation
```bash
cd backend
uv run pytest -v
uv run ruff check app/ tests/
```
