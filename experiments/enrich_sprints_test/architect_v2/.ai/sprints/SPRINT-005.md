# Sprint 005 — Messaging Engine & Post-Shift Engagement (enriched spec, additive)

## Scope
Add a templated messaging engine with pluggable delivery adapters (Console default, Twilio stub), the messaging service that creates Message rows for lifecycle events (confirmation, reminder, arrival, post-shift impact), plus engagement endpoints (impact card, next-commitment, giving interest).

## Non-goals
- No models.py / schemas.py edits — `Message`, `GivingInterest`, `MessageType`, `MessageStatus` defined in Sprint 001
- No automatic scheduling/cron (sprint focuses on the on-demand send + read API)
- No real Twilio API call (stub adapter only)

## Dependencies
- Sprint 001: `app.models` exposes `Volunteer, Message, MessageType, MessageStatus, GivingInterest, Registration, Shift`
- Sprint 001: `app.schemas` exposes `MessageRead, ImpactCardResponse, NextCommitmentRequest, GivingInterestRequest`
- Sprint 001: `app.config.get_settings` exposes `SMS_ADAPTER` (default "console")
- Sprint 001: `app.dependencies.get_current_volunteer`
- Sprint 002: `Registration` rows exist for `next-commitment` to create new ones via shift_id

## Python/runtime conventions (inherited from Sprint 001)
All conventions inherited.

## File structure

```
backend/app/services/messaging.py            — render_template, send_message
backend/app/services/messaging_adapters.py   — MessageAdapter Protocol, ConsoleAdapter, TwilioAdapter (stub)
backend/app/routers/messages.py              — GET /messages/me, POST /messages/{id}/resend
backend/app/routers/engagement.py            — GET /engagement/impact-card/{registration_id}, POST /engagement/next-commitment, POST /engagement/giving-interest
backend/tests/test_messaging.py              — service tests (templates, send via console)
backend/tests/test_engagement.py             — endpoint tests
```

## Interface contract

### `backend/app/services/messaging_adapters.py`
```python
class MessageAdapter(Protocol):
    async def send(self, phone: str, content: str) -> bool: ...

class ConsoleAdapter:
    async def send(self, phone: str, content: str) -> bool:
        """Logs to stdout via logging.info; always returns True."""

class TwilioAdapter:
    """Stub — does not call Twilio API in this sprint. Returns True if SID/token configured else False."""
    def __init__(self, account_sid: str, auth_token: str, from_number: str): ...
    async def send(self, phone: str, content: str) -> bool: ...

def get_adapter() -> MessageAdapter:
    """Reads settings.SMS_ADAPTER and returns ConsoleAdapter or TwilioAdapter."""
```

### `backend/app/services/messaging.py`
```python
TEMPLATES: dict[MessageType, str] = {
    MessageType.confirmation: "Hi {first_name}, your registration for {shift_title} on {shift_date} is confirmed.",
    MessageType.reminder: "Reminder: {shift_title} is tomorrow at {start_time}. See you at {location_name}.",
    MessageType.arrival_instructions: "You're at the right place! Show your QR code at the front desk.",
    MessageType.post_shift_impact: "Thank you {first_name}! You served {hours} hours at {shift_title}. Together we made an impact!",
}

async def render_template(message_type: MessageType, context: dict) -> str:
    """Substitutes {key} placeholders. Missing keys raise KeyError."""

async def send_message(
    volunteer: Volunteer,
    message_type: MessageType,
    context: dict,
    db: AsyncSession,
    registration_id: uuid.UUID | None = None,
) -> Message:
    """Renders template, persists Message(status=pending), invokes adapter; updates status=sent or failed and sent_at."""
```

### `backend/app/routers/messages.py`
```python
router = APIRouter(prefix="/messages", tags=["messages"])

@router.get("/me", response_model=list[MessageRead])
async def my_messages(
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> list[MessageRead]: ...

@router.post("/{message_id}/resend", response_model=MessageRead)
async def resend_message(
    message_id: uuid.UUID,
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> MessageRead:
    """Re-sends an existing message via the current adapter; updates status."""
```

### `backend/app/routers/engagement.py`
```python
router = APIRouter(prefix="/engagement", tags=["engagement"])

@router.get("/impact-card/{registration_id}", response_model=ImpactCardResponse)
async def impact_card(
    registration_id: uuid.UUID,
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> ImpactCardResponse:
    """Returns shift_title, hours (computed from start_time/end_time), impact_metric (string)."""

@router.post("/next-commitment", response_model=RegistrationRead, status_code=201)
async def next_commitment(
    req: NextCommitmentRequest,
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> RegistrationRead:
    """Creates a new Registration for the given shift_id (delegates to same logic as Sprint 002 — capacity, duplicate, etc.)."""

@router.post("/giving-interest", status_code=201)
async def giving_interest(
    req: GivingInterestRequest,
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Creates GivingInterest row. Returns {"recorded": true}."""
```

## Imports per file

**`backend/app/services/messaging_adapters.py`**
```python
import logging
from typing import Protocol
from app.config import get_settings
```

**`backend/app/services/messaging.py`**
```python
import uuid
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import Volunteer, Message, MessageType, MessageStatus
from app.services.messaging_adapters import get_adapter
```

**`backend/app/routers/messages.py`**
```python
import uuid
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.dependencies import get_current_volunteer
from app.exceptions import AppError, NOT_FOUND, FORBIDDEN
from app.models import Volunteer, Message, MessageStatus
from app.schemas import MessageRead
from app.services.messaging_adapters import get_adapter
```

**`backend/app/routers/engagement.py`**
```python
import uuid
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.dependencies import get_current_volunteer
from app.exceptions import AppError, NOT_FOUND, FORBIDDEN, SHIFT_FULL, DUPLICATE_REGISTRATION
from app.models import Volunteer, Registration, Shift, GivingInterest, RegistrationStatus
from app.schemas import (
    ImpactCardResponse, NextCommitmentRequest, GivingInterestRequest, RegistrationRead,
)
```

**`backend/tests/test_messaging.py`** / **`test_engagement.py`**
```python
import pytest
import uuid
from datetime import date, time, timedelta
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import Volunteer, Message, MessageType, MessageStatus, Registration, GivingInterest
from app.services.messaging import render_template, send_message
from app.services.messaging_adapters import ConsoleAdapter, get_adapter
```

## Algorithm notes

### `render_template` — substitution implementation
```python
async def render_template(message_type, context):
    template = TEMPLATES[message_type]
    return template.format(**context)
```

### `send_message` — persist + dispatch
```python
async def send_message(volunteer, message_type, context, db, registration_id=None):
    content = await render_template(message_type, context)
    msg = Message(
        volunteer_id=volunteer.id,
        registration_id=registration_id,
        message_type=message_type,
        content=content,
        status=MessageStatus.pending,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)

    adapter = get_adapter()
    success = await adapter.send(volunteer.phone or "", content)
    msg.status = MessageStatus.sent if success else MessageStatus.failed
    if success:
        msg.sent_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(msg)
    return msg
```

### `get_adapter` — settings-driven
```python
def get_adapter():
    s = get_settings()
    if s.SMS_ADAPTER == "twilio" and s.TWILIO_ACCOUNT_SID and s.TWILIO_AUTH_TOKEN and s.TWILIO_FROM_NUMBER:
        return TwilioAdapter(s.TWILIO_ACCOUNT_SID, s.TWILIO_AUTH_TOKEN, s.TWILIO_FROM_NUMBER)
    return ConsoleAdapter()
```

### `impact_card` — computes hours from shift times
```python
@router.get("/impact-card/{registration_id}", response_model=ImpactCardResponse)
async def impact_card(registration_id, volunteer, db):
    reg = (await db.execute(
        select(Registration).where(Registration.id == registration_id)
    )).scalar_one_or_none()
    if reg is None:
        raise AppError(404, "Registration not found", NOT_FOUND)
    if reg.volunteer_id != volunteer.id:
        raise AppError(403, "Not your registration", FORBIDDEN)

    shift = (await db.execute(select(Shift).where(Shift.id == reg.shift_id))).scalar_one()
    # Compute hours
    start_dt = datetime.combine(shift.date, shift.start_time)
    end_dt = datetime.combine(shift.date, shift.end_time)
    hours = (end_dt - start_dt).total_seconds() / 3600

    return ImpactCardResponse(
        shift_title=shift.title,
        hours=hours,
        impact_metric=f"You helped serve {int(hours * 50)} meals this shift",
    )
```

## Test plan

### `backend/tests/test_messaging.py`
```python
async def test_render_confirmation_template(): ...
async def test_render_template_missing_key_raises(): ...
async def test_send_message_persists_pending_then_sent(db_session, test_volunteer): ...
async def test_console_adapter_returns_true(): ...
async def test_get_adapter_returns_console_by_default(): ...
async def test_send_message_via_console_marks_sent(db_session, test_volunteer): ...
```

### `backend/tests/test_engagement.py`
```python
async def test_impact_card_returns_hours(client, auth_headers, test_volunteer, test_shift, db_session): ...
async def test_impact_card_for_other_volunteer_returns_403(client, db_session, test_shift): ...
async def test_next_commitment_creates_registration(client, auth_headers, test_shift): ...
async def test_giving_interest_persists(client, auth_headers, db_session): ...
async def test_my_messages_returns_list(client, auth_headers, test_volunteer, db_session): ...
async def test_resend_message_marks_sent(client, auth_headers, test_volunteer, db_session): ...
```

## Rules
- New files only — no edits to Sprint 001 files
- ConsoleAdapter logs via `logging.info` (not `print`) for testability
- TwilioAdapter is a stub — does NOT call the real Twilio API in this sprint

## New files
- `backend/app/services/messaging.py` — render_template, send_message, TEMPLATES dict
- `backend/app/services/messaging_adapters.py` — MessageAdapter Protocol, ConsoleAdapter, TwilioAdapter (stub), get_adapter
- `backend/app/routers/messages.py` — GET /messages/me, POST /messages/{id}/resend
- `backend/app/routers/engagement.py` — impact-card, next-commitment, giving-interest
- `backend/tests/test_messaging.py`
- `backend/tests/test_engagement.py`

## Modified files
(none)

## Expected Artifacts
- `backend/app/services/messaging.py`
- `backend/app/services/messaging_adapters.py`
- `backend/app/routers/messages.py`
- `backend/app/routers/engagement.py`
- `backend/tests/test_messaging.py`
- `backend/tests/test_engagement.py`

## DoD
- [ ] `cd backend && uv run pytest tests/test_messaging.py -v` passes (6 subtests)
- [ ] `cd backend && uv run pytest tests/test_engagement.py -v` passes (6 subtests)
- [ ] All prior sprint tests still green
- [ ] `cd backend && uv run ruff check app/ tests/` clean

## Validation
```bash
cd backend
uv run pytest -v
uv run ruff check app/ tests/
```
