# Sprint 003 — Groups, Waivers & Orientation (enriched spec, additive)

## Scope
Add router files for group registrations (volunteer-led signups bringing other volunteers along), waiver acceptance flow, and orientation completion tracking. **All foundation models/schemas/exceptions are FROZEN from Sprint 001 — only new router and test files in this sprint.**

## Non-goals
- No models.py / schemas.py / main.py edits
- No QR check-in (Sprint 006 reads waiver+orientation status; this sprint just defines the endpoints)
- No admin UI for waiver/orientation review (frontend sprints)

## Dependencies
- Sprint 001: `app.models` exposes `Volunteer, Group, GroupMember, WaiverAcceptance, OrientationCompletion`
- Sprint 001: `app.schemas` exposes `GroupCreate, GroupRead, GroupMemberAdd, WaiverSignRequest, WaiverStatusResponse, OrientationCompleteRequest, OrientationStatusResponse`
- Sprint 001: `app.dependencies.get_current_volunteer`, `app.exceptions.AppError, NOT_FOUND, FORBIDDEN`
- Sprint 001's `pkgutil` auto-discovery in `main.py` picks up new router files

## Python/runtime conventions (inherited from Sprint 001)
All conventions inherited.

## File structure

```
backend/app/routers/groups.py            — POST/GET /groups, POST /groups/{id}/members
backend/app/routers/waivers.py           — POST /waivers/sign, GET /waivers/me/status
backend/app/routers/orientation.py       — POST /orientation/complete, GET /orientation/me/status
backend/tests/test_groups.py             — group create/list/add-member tests
backend/tests/test_waivers.py            — waiver sign + idempotency + status tests
backend/tests/test_orientation.py        — orientation complete + status tests
```

## Interface contract

### `backend/app/routers/groups.py`
```python
router = APIRouter(prefix="/groups", tags=["groups"])

@router.post("", response_model=GroupRead, status_code=201)
async def create_group(
    req: GroupCreate,
    leader: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> GroupRead:
    """Creates a Group with leader_id=leader.id. Returns the persisted record."""

@router.get("", response_model=list[GroupRead])
async def list_my_groups(
    leader: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> list[GroupRead]:
    """Returns groups where the current volunteer is the leader."""

@router.post("/{group_id}/members", response_model=GroupRead, status_code=201)
async def add_member(
    group_id: uuid.UUID,
    req: GroupMemberAdd,
    leader: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> GroupRead:
    """AppError(404) if group missing; AppError(403) if caller is not the group leader."""
```

### `backend/app/routers/waivers.py`
```python
router = APIRouter(prefix="/waivers", tags=["waivers"])

@router.post("/sign", response_model=WaiverStatusResponse, status_code=201)
async def sign_waiver(
    req: WaiverSignRequest,
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> WaiverStatusResponse:
    """Idempotent — repeated calls return the existing acceptance, do not create duplicates."""

@router.get("/me/status", response_model=WaiverStatusResponse)
async def my_waiver_status(
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> WaiverStatusResponse: ...
```

### `backend/app/routers/orientation.py`
```python
router = APIRouter(prefix="/orientation", tags=["orientation"])

@router.post("/complete", response_model=OrientationStatusResponse, status_code=201)
async def complete_orientation(
    req: OrientationCompleteRequest,
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> OrientationStatusResponse:
    """Idempotent — repeat call returns existing completion."""

@router.get("/me/status", response_model=OrientationStatusResponse)
async def my_orientation_status(
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> OrientationStatusResponse: ...
```

## Imports per file

**`backend/app/routers/groups.py`**
```python
import uuid
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.dependencies import get_current_volunteer
from app.exceptions import AppError, NOT_FOUND, FORBIDDEN
from app.models import Volunteer, Group, GroupMember
from app.schemas import GroupCreate, GroupRead, GroupMemberAdd
```

**`backend/app/routers/waivers.py`**
```python
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.dependencies import get_current_volunteer
from app.models import Volunteer, WaiverAcceptance
from app.schemas import WaiverSignRequest, WaiverStatusResponse
```

**`backend/app/routers/orientation.py`**
```python
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.dependencies import get_current_volunteer
from app.models import Volunteer, OrientationCompletion
from app.schemas import OrientationCompleteRequest, OrientationStatusResponse
```

**`backend/tests/test_groups.py`** / **`test_waivers.py`** / **`test_orientation.py`**
```python
import pytest
import uuid
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import Volunteer, Group, GroupMember, WaiverAcceptance, OrientationCompletion
```

## Algorithm notes

### Idempotent waiver sign (the pattern reused for orientation)
```python
@router.post("/sign", response_model=WaiverStatusResponse, status_code=201)
async def sign_waiver(req, volunteer, db):
    existing = (await db.execute(
        select(WaiverAcceptance).where(WaiverAcceptance.volunteer_id == volunteer.id)
    )).scalar_one_or_none()
    if existing is not None:
        return WaiverStatusResponse(signed=True, signed_at=existing.signed_at)
    waiver = WaiverAcceptance(volunteer_id=volunteer.id)
    db.add(waiver)
    await db.commit()
    await db.refresh(waiver)
    return WaiverStatusResponse(signed=True, signed_at=waiver.signed_at)
```

### Group leader authorization in `add_member`
```python
@router.post("/{group_id}/members", response_model=GroupRead, status_code=201)
async def add_member(group_id, req, leader, db):
    group = (await db.execute(select(Group).where(Group.id == group_id))).scalar_one_or_none()
    if group is None:
        raise AppError(404, "Group not found", NOT_FOUND)
    if group.leader_id != leader.id:
        raise AppError(403, "Only the group leader can add members", FORBIDDEN)
    db.add(GroupMember(group_id=group_id, volunteer_id=req.volunteer_id))
    await db.commit()
    await db.refresh(group)
    return group
```

## Test plan

### `backend/tests/test_groups.py`
```python
async def test_create_group_returns_201(client, auth_headers): ...
async def test_list_my_groups(client, auth_headers): ...
async def test_add_member_to_my_group(client, auth_headers, db_session): ...
async def test_add_member_to_other_group_returns_403(client, db_session): ...
async def test_add_member_to_nonexistent_group_returns_404(client, auth_headers): ...
```

### `backend/tests/test_waivers.py`
```python
async def test_sign_waiver(client, auth_headers): ...
async def test_sign_waiver_idempotent(client, auth_headers): ...     # second sign returns same signed_at
async def test_waiver_status_signed(client, auth_headers): ...
async def test_waiver_status_unsigned(client, auth_headers): ...     # before signing, signed=False
async def test_waiver_sign_unauthenticated(client): ...              # 401
```

### `backend/tests/test_orientation.py`
```python
async def test_complete_orientation(client, auth_headers): ...
async def test_complete_orientation_idempotent(client, auth_headers): ...
async def test_orientation_status_completed(client, auth_headers): ...
async def test_orientation_status_not_completed(client, auth_headers): ...
```

## Rules
- New files only — no edits to Sprint 001 files
- Idempotent endpoints (waiver/orientation) MUST not create duplicate rows; the model has `unique=True` on `volunteer_id` to enforce this at DB level

## New files
- `backend/app/routers/groups.py` — group CRUD with leader-only authorization for adding members
- `backend/app/routers/waivers.py` — waiver sign + status (idempotent)
- `backend/app/routers/orientation.py` — orientation complete + status (idempotent)
- `backend/tests/test_groups.py`
- `backend/tests/test_waivers.py`
- `backend/tests/test_orientation.py`

## Modified files
(none)

## Expected Artifacts
- `backend/app/routers/groups.py`
- `backend/app/routers/waivers.py`
- `backend/app/routers/orientation.py`
- `backend/tests/test_groups.py`
- `backend/tests/test_waivers.py`
- `backend/tests/test_orientation.py`

## DoD
- [ ] `cd backend && uv run pytest tests/test_groups.py -v` passes
- [ ] `cd backend && uv run pytest tests/test_waivers.py -v` passes
- [ ] `cd backend && uv run pytest tests/test_orientation.py -v` passes
- [ ] All Sprint 001 + 002 tests still green
- [ ] `cd backend && uv run ruff check app/ tests/` clean

## Validation
```bash
cd backend
uv run pytest -v
uv run ruff check app/ tests/
```
