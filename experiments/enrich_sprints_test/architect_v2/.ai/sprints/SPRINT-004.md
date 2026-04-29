# Sprint 004 — Opportunity Discovery & Preference Matching (enriched spec, additive)

## Scope
Add a discovery service that scores available shifts against a volunteer's preferences (date availability, environment, labor condition, location), plus a router exposing `POST /discovery/recommendations`. Score is a deterministic weighted-rule function — no ML.

## Non-goals
- No models.py / schemas.py edits — `DiscoveryRequest` and `DiscoveryResult` are defined in Sprint 001
- No personalization based on past activity (future enhancement)
- No ML or embeddings

## Dependencies
- Sprint 001: `app.schemas` exposes `DiscoveryRequest, DiscoveryResult`
- Sprint 001: `app.models` exposes `Shift, Station, Location, EnvironmentType, LaborCondition, RegistrationStatus, Registration`
- Sprint 002: shifts and stations exist in the DB (the service queries them)
- Sprint 001's pkgutil auto-discovery picks up the new router

## Python/runtime conventions (inherited from Sprint 001)
All conventions inherited.

## File structure

```
backend/app/services/discovery.py        — score_shifts(preferences, available_shifts) -> list[DiscoveryResult]
backend/app/routers/discovery.py         — POST /discovery/recommendations
backend/tests/test_discovery_service.py  — unit tests on score_shifts
backend/tests/test_discovery_router.py   — endpoint integration tests
```

## Interface contract

### `backend/app/services/discovery.py`
```python
async def score_shifts(
    preferences: DiscoveryRequest,
    available_shifts: list[Shift],
    db: AsyncSession,
) -> list[DiscoveryResult]:
    """
    Returns DiscoveryResults sorted by score descending. Score formula:
      base = 1.0
      + 2.0 if shift.date in preferences.available_dates (else 0; required if available_dates given)
      + 1.0 if any station of shift.location matches preferences.preferred_environment
      + 1.0 if any station of shift.location matches preferences.preferred_labor_condition
      + 0.5 if shift.location_id in preferences.location_ids
    Capacity filter: shifts at or above max_volunteers (active registrations) get score=0.
    """
```

### `backend/app/routers/discovery.py`
```python
router = APIRouter(prefix="/discovery", tags=["discovery"])

@router.post("/recommendations", response_model=list[DiscoveryResult])
async def recommendations(
    req: DiscoveryRequest,
    db: AsyncSession = Depends(get_db),
) -> list[DiscoveryResult]:
    """Loads all upcoming shifts (date >= today), passes them through score_shifts, returns sorted results."""
```

## Imports per file

**`backend/app/services/discovery.py`**
```python
from datetime import date
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import Shift, Station, Location, Registration, RegistrationStatus
from app.schemas import DiscoveryRequest, DiscoveryResult
```

**`backend/app/routers/discovery.py`**
```python
from datetime import date
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models import Shift
from app.schemas import DiscoveryRequest, DiscoveryResult
from app.services.discovery import score_shifts
```

**`backend/tests/test_discovery_service.py`** / **`test_discovery_router.py`**
```python
import pytest
import uuid
from datetime import date, time, timedelta
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import (
    Shift, Station, Location, Registration, RegistrationStatus,
    EnvironmentType, LaborCondition,
)
from app.schemas import DiscoveryRequest
from app.services.discovery import score_shifts
```

## Algorithm notes

### `score_shifts` — verbatim implementation
```python
async def score_shifts(preferences, available_shifts, db):
    results = []
    for shift in available_shifts:
        # Capacity filter
        active_count = (await db.execute(
            select(func.count(Registration.id)).where(
                Registration.shift_id == shift.id,
                Registration.status != RegistrationStatus.cancelled,
            )
        )).scalar_one()
        if active_count >= shift.max_volunteers:
            results.append(DiscoveryResult(shift_id=shift.id, score=0.0, explanation="full"))
            continue

        # Date availability — strict requirement if specified
        if preferences.available_dates and shift.date not in preferences.available_dates:
            results.append(DiscoveryResult(
                shift_id=shift.id, score=0.0, explanation="date not in your availability",
            ))
            continue

        score = 1.0
        reasons = ["matches your preferences"]
        if preferences.available_dates:
            score += 2.0
            reasons.append(f"on {shift.date.isoformat()}")

        # Load stations of this shift's location
        stations = (await db.execute(
            select(Station).where(Station.location_id == shift.location_id)
        )).scalars().all()

        if preferences.preferred_environment is not None:
            if any(s.environment_type == preferences.preferred_environment for s in stations):
                score += 1.0
                reasons.append(f"{preferences.preferred_environment.value} environment available")

        if preferences.preferred_labor_condition is not None:
            if any(s.labor_condition == preferences.preferred_labor_condition for s in stations):
                score += 1.0
                reasons.append(f"{preferences.preferred_labor_condition.value} work available")

        if preferences.location_ids and shift.location_id in preferences.location_ids:
            score += 0.5
            reasons.append("at preferred location")

        results.append(DiscoveryResult(
            shift_id=shift.id, score=score,
            explanation="; ".join(reasons),
        ))

    results.sort(key=lambda r: r.score, reverse=True)
    return results
```

## Test plan

### `backend/tests/test_discovery_service.py` — unit tests
```python
async def test_score_includes_base_when_no_preferences(db_session, test_shift): ...  # base 1.0
async def test_score_excludes_full_shifts(db_session, test_shift): ...               # at-cap → 0.0
async def test_score_requires_date_match_when_dates_given(db_session, test_shift): ... # date mismatch → 0.0
async def test_score_adds_bonus_for_environment_match(db_session, test_shift, test_station): ...
async def test_score_adds_bonus_for_labor_condition_match(db_session, test_shift, test_station): ...
async def test_score_adds_bonus_for_location_match(db_session, test_shift): ...
async def test_results_sorted_descending(db_session, test_location): ...             # multiple shifts, verify ordering
```

### `backend/tests/test_discovery_router.py` — endpoint
```python
async def test_recommendations_endpoint_returns_200(client, test_shift): ...
async def test_recommendations_excludes_past_shifts(client, db_session, test_location): ...
async def test_recommendations_unauthenticated_allowed(client, test_shift): ...      # discovery does not require auth
```

## Rules
- New files only — no edits to Sprint 001 files
- The score formula is deterministic — same inputs produce same outputs (testable)

## New files
- `backend/app/services/discovery.py` — `score_shifts` function
- `backend/app/routers/discovery.py` — discovery router
- `backend/tests/test_discovery_service.py`
- `backend/tests/test_discovery_router.py`

## Modified files
(none)

## Expected Artifacts
- `backend/app/services/discovery.py`
- `backend/app/routers/discovery.py`
- `backend/tests/test_discovery_service.py`
- `backend/tests/test_discovery_router.py`

## DoD
- [ ] `cd backend && uv run pytest tests/test_discovery_service.py -v` passes
- [ ] `cd backend && uv run pytest tests/test_discovery_router.py -v` passes
- [ ] All prior sprint tests still green
- [ ] `cd backend && uv run ruff check app/ tests/` clean

## Validation
```bash
cd backend
uv run pytest -v
uv run ruff check app/ tests/
```
