# Sprint 001 — Foundation (full schema + auth) (enriched spec, front-loaded)

## Scope
Front-load the entire backend foundation: every model, every Pydantic schema, every shared exception type, every test fixture, plus the FastAPI app factory with auto-discovering router registration. Implement the first feature (phone OTP authentication with JWT, register endpoint, /health) as the working slice. Subsequent sprints add only new router/service files — no schema or main.py modifications.

## Non-goals
- No frontend, Docker, or CI (Sprint 016)
- No SMS gateway integration — OTP logged to console (Sprint 005 adds Twilio adapter)
- No CRM sync, donor matching, skills, court, or benefits logic (Sprints 011–013) — but their MODELS and SCHEMAS are defined here
- No orientation video content management (Sprint 003 adds endpoints; this sprint just declares the model)
- No alembic migrations — `init_db.py` script creates all tables via `Base.metadata.create_all`

## Dependencies
None — this is the first sprint and establishes the foundation every later sprint imports.

## Python/runtime conventions
- **Module:** `backend/app` package; all internal imports as `from app.models import Volunteer` (NOT `from backend.app.models import ...`)
- **Python:** 3.12+; `uv` for all commands (`uv run pytest`, `uv run ruff check`)
- **Framework:** `fastapi`; ASGI server: `uvicorn[standard]`
- **ORM:** `sqlalchemy[asyncio]` 2.0+ with `AsyncSession`; driver: `asyncpg` (prod), `aiosqlite` (tests)
- **Validation:** `pydantic` v2 with `model_config = ConfigDict(from_attributes=True)` for ORM schemas
- **Settings:** `pydantic-settings` `BaseSettings`
- **Auth:** `python-jose[cryptography]` for JWT; algorithm `HS256`
- **Testing:** `pytest` + `pytest-asyncio` (mode=auto) + `httpx.AsyncClient`
- **Error pattern:** `AppError(status_code, detail, error_code)` subclass of `HTTPException`; all errors return `{"detail": "...", "error_code": "UPPER_SNAKE"}`
- **All timestamps:** UTC `datetime`; all IDs: `uuid.UUID` server-generated via `uuid.uuid4`
- **Linter:** `ruff`

## Architectural choice — auto-discovering routers (load-bearing for front-loading)
`main.py` does NOT import each router by name. Instead it uses `pkgutil.iter_modules` to scan `app.routers/`, and registers any module that exports a `router: APIRouter` symbol. This means later sprints just drop a new file in `app/routers/` and it's auto-included. **No `main.py` modification ever needed across sprints.** Router files set their own `prefix` and `tags` on the `APIRouter()` they expose.

## File structure

```
backend/pyproject.toml                         — full manifest with all 16-sprint dependencies declared
backend/app/__init__.py                        — empty package marker
backend/app/config.py                          — Settings (BaseSettings) with full env var set
backend/app/database.py                        — Base, async engine, AsyncSessionLocal, get_db dependency
backend/app/exceptions.py                      — AppError, all error code constants for every sprint
backend/app/models.py                          — every ORM model + every enum across all 16 sprints
backend/app/schemas.py                         — every Pydantic request/response schema across all 16 sprints
backend/app/auth.py                            — JWT helpers (Sprint 001 feature)
backend/app/dependencies.py                    — get_db, get_current_volunteer, oauth2_scheme
backend/app/main.py                            — FastAPI app factory with pkgutil-based router auto-discovery
backend/app/routers/__init__.py                — empty package marker
backend/app/routers/auth.py                    — Sprint 001 feature: POST /auth/otp/send, /otp/verify, /register
backend/app/services/__init__.py               — empty package marker
backend/scripts/init_db.py                     — async runner: Base.metadata.create_all
backend/tests/__init__.py                      — empty package marker
backend/tests/conftest.py                      — every fixture across all sprints (factories for every model, async client, auth helpers)
backend/tests/test_auth.py                     — Sprint 001 feature tests
backend/tests/test_health.py                   — /health smoke test
backend/tests/test_config.py                   — Settings load test
backend/tests/test_models.py                   — model unit tests for EVERY model defined in this sprint (foundation health check)
```

## Interface contract

### `backend/app/exceptions.py`
```python
from fastapi import HTTPException


# Error code constants — used across every sprint
ACCOUNT_EXISTS = "ACCOUNT_EXISTS"
INVALID_OTP = "INVALID_OTP"
OTP_EXPIRED = "OTP_EXPIRED"
NOT_FOUND = "NOT_FOUND"
UNAUTHORIZED = "UNAUTHORIZED"
FORBIDDEN = "FORBIDDEN"
SHIFT_FULL = "SHIFT_FULL"
DUPLICATE_REGISTRATION = "DUPLICATE_REGISTRATION"
WAIVER_REQUIRED = "WAIVER_REQUIRED"
ORIENTATION_REQUIRED = "ORIENTATION_REQUIRED"
INVALID_QR = "INVALID_QR"
ASSIGNMENT_CONFLICT = "ASSIGNMENT_CONFLICT"
SYNC_FAILED = "SYNC_FAILED"
MATCH_AMBIGUOUS = "MATCH_AMBIGUOUS"
FILE_TOO_LARGE = "FILE_TOO_LARGE"
INVALID_FILE_TYPE = "INVALID_FILE_TYPE"
HOURS_INSUFFICIENT = "HOURS_INSUFFICIENT"


class AppError(HTTPException):
    """Single exception class used across all routers. Returns JSON: {"detail": ..., "error_code": ...}"""
    def __init__(self, status_code: int, detail: str, error_code: str) -> None:
        super().__init__(status_code=status_code, detail=detail)
        self.error_code = error_code
```

### `backend/app/config.py`
```python
from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    DATABASE_URL: str = "sqlite+aiosqlite:///./nifb.db"
    SECRET_KEY: str = "change-me-in-production"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days
    OTP_EXPIRY_MINUTES: int = 10
    DEV_OTP_BYPASS: bool = True
    OTP_BYPASS_CODE: str = "000000"
    SMS_ADAPTER: str = "console"  # "console" | "twilio"
    TWILIO_ACCOUNT_SID: str | None = None
    TWILIO_AUTH_TOKEN: str | None = None
    TWILIO_FROM_NUMBER: str | None = None
    UPLOAD_DIR: str = "./uploads"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

### `backend/app/database.py`
```python
from collections.abc import AsyncGenerator
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from app.config import get_settings


class Base(DeclarativeBase):
    pass


_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def get_engine() -> AsyncEngine:
    global _engine
    if _engine is None:
        _engine = create_async_engine(get_settings().DATABASE_URL, echo=False)
    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    global _session_factory
    if _session_factory is None:
        _session_factory = async_sessionmaker(get_engine(), expire_on_commit=False)
    return _session_factory


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    factory = get_session_factory()
    async with factory() as session:
        yield session
```

### `backend/app/models.py` — ALL models for ALL sprints
```python
import enum
import uuid
from datetime import date, datetime, time
from sqlalchemy import ForeignKey, String, Text, Float, Boolean, DateTime, Integer, Date, Time
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import func
from app.database import Base


# ─── Enums ────────────────────────────────────────────────
class RegistrationStatus(str, enum.Enum):
    registered = "registered"
    cancelled = "cancelled"
    checked_in = "checked_in"


class VolunteerPathway(str, enum.Enum):
    general = "general"
    skills_based = "skills_based"
    court_required = "court_required"
    benefits = "benefits"


class MessageType(str, enum.Enum):
    confirmation = "confirmation"
    reminder = "reminder"
    arrival_instructions = "arrival_instructions"
    post_shift_impact = "post_shift_impact"


class MessageStatus(str, enum.Enum):
    pending = "pending"
    sent = "sent"
    failed = "failed"


class EnvironmentType(str, enum.Enum):
    indoor = "indoor"
    outdoor = "outdoor"
    mobile = "mobile"


class LaborCondition(str, enum.Enum):
    standing = "standing"
    sitting = "sitting"
    mobile = "mobile"


class ReviewStatus(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"


# ─── Sprint 001 models ────────────────────────────────────
class Volunteer(Base):
    __tablename__ = "volunteers"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True, index=True)
    phone: Mapped[str | None] = mapped_column(String(20), unique=True, nullable=True, index=True)
    first_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    last_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    pathway: Mapped[VolunteerPathway] = mapped_column(default=VolunteerPathway.general)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class OTP(Base):
    __tablename__ = "otps"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    phone: Mapped[str] = mapped_column(String(20), index=True)
    code: Mapped[str] = mapped_column(String(6))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


# ─── Sprint 002 models ────────────────────────────────────
class Location(Base):
    __tablename__ = "locations"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(200))
    address: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    stations: Mapped[list["Station"]] = relationship(back_populates="location")


class Station(Base):
    __tablename__ = "stations"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    location_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("locations.id"))
    name: Mapped[str] = mapped_column(String(200))
    max_capacity: Mapped[int]
    environment_type: Mapped[EnvironmentType]
    labor_condition: Mapped[LaborCondition]
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    location: Mapped["Location"] = relationship(back_populates="stations")


class Shift(Base):
    __tablename__ = "shifts"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    location_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("locations.id"))
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    date: Mapped[date]
    start_time: Mapped[time]
    end_time: Mapped[time]
    max_volunteers: Mapped[int]
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    location: Mapped["Location"] = relationship()
    registrations: Mapped[list["Registration"]] = relationship(back_populates="shift")


class Registration(Base):
    __tablename__ = "registrations"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    shift_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("shifts.id"))
    group_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("groups.id"), nullable=True)
    status: Mapped[RegistrationStatus] = mapped_column(default=RegistrationStatus.registered)
    checked_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    volunteer: Mapped["Volunteer"] = relationship()
    shift: Mapped["Shift"] = relationship(back_populates="registrations")


# ─── Sprint 003 models ────────────────────────────────────
class Group(Base):
    __tablename__ = "groups"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(200))
    leader_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    leader: Mapped["Volunteer"] = relationship()
    members: Mapped[list["GroupMember"]] = relationship(back_populates="group")


class GroupMember(Base):
    __tablename__ = "group_members"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id"))
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    group: Mapped["Group"] = relationship(back_populates="members")
    volunteer: Mapped["Volunteer"] = relationship()


class WaiverAcceptance(Base):
    __tablename__ = "waiver_acceptances"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"), unique=True)
    signed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class OrientationCompletion(Base):
    __tablename__ = "orientation_completions"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"), unique=True)
    completed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


# ─── Sprint 005 models ────────────────────────────────────
class Message(Base):
    __tablename__ = "messages"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    registration_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("registrations.id"), nullable=True)
    message_type: Mapped[MessageType]
    content: Mapped[str] = mapped_column(Text)
    status: Mapped[MessageStatus] = mapped_column(default=MessageStatus.pending)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class GivingInterest(Base):
    __tablename__ = "giving_interests"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    interested_in_monthly: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


# ─── Sprint 007 models ────────────────────────────────────
class Assignment(Base):
    __tablename__ = "assignments"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    station_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("stations.id"))
    shift_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("shifts.id"))
    is_manual_override: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


# ─── Sprint 011 models ────────────────────────────────────
class SyncRecord(Base):
    __tablename__ = "sync_records"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    re_nxt_constituent_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    sync_status: Mapped[str] = mapped_column(String(50))
    synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class MatchException(Base):
    __tablename__ = "match_exceptions"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    candidate_re_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    confidence_score: Mapped[float]
    match_details: Mapped[str] = mapped_column(Text)
    resolved: Mapped[bool] = mapped_column(default=False)
    resolved_by: Mapped[str | None] = mapped_column(String(100), nullable=True)
    resolution: Mapped[str | None] = mapped_column(String(50), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


# ─── Sprint 012 models ────────────────────────────────────
class SkillsApplication(Base):
    __tablename__ = "skills_applications"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    resume_url: Mapped[str] = mapped_column(String(500))
    skills_description: Mapped[str | None] = mapped_column(Text, nullable=True)
    review_status: Mapped[ReviewStatus] = mapped_column(default=ReviewStatus.pending)
    reviewer_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


# ─── Sprint 013 models ────────────────────────────────────
class CourtServiceRecord(Base):
    __tablename__ = "court_service_records"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    case_number: Mapped[str] = mapped_column(String(100))
    required_hours: Mapped[float]
    completed_hours: Mapped[float] = mapped_column(default=0.0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class BenefitsRecord(Base):
    __tablename__ = "benefits_records"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    program_type: Mapped[str] = mapped_column(String(100))
    required_hours: Mapped[float]
    completed_hours: Mapped[float] = mapped_column(default=0.0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
```

### `backend/app/schemas.py` — ALL Pydantic schemas for ALL sprints
```python
import uuid
from datetime import date, datetime, time
from pydantic import BaseModel, ConfigDict
from app.models import (
    RegistrationStatus, VolunteerPathway, MessageType, MessageStatus,
    EnvironmentType, LaborCondition, ReviewStatus,
)


# ─── Sprint 001 schemas ───────────────────────────────────
class OTPSendRequest(BaseModel):
    phone: str

class OTPSendResponse(BaseModel):
    message: str

class OTPVerifyRequest(BaseModel):
    phone: str
    code: str

class OTPVerifyResponse(BaseModel):
    access_token: str
    is_new: bool
    volunteer_id: uuid.UUID

class RegisterRequest(BaseModel):
    phone: str | None = None
    email: str | None = None
    first_name: str
    last_name: str

class RegisterResponse(BaseModel):
    id: uuid.UUID
    email: str | None
    phone: str | None
    access_token: str

class VolunteerRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    email: str | None
    phone: str | None
    first_name: str | None
    last_name: str | None
    pathway: VolunteerPathway
    created_at: datetime

class VolunteerUpdate(BaseModel):
    email: str | None = None
    first_name: str | None = None
    last_name: str | None = None

class HealthResponse(BaseModel):
    status: str

class ErrorResponse(BaseModel):
    detail: str
    error_code: str


# ─── Sprint 002 schemas ───────────────────────────────────
class LocationCreate(BaseModel):
    name: str
    address: str | None = None

class LocationRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    address: str | None
    created_at: datetime

class StationCreate(BaseModel):
    name: str
    max_capacity: int
    environment_type: EnvironmentType
    labor_condition: LaborCondition

class StationRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    location_id: uuid.UUID
    name: str
    max_capacity: int
    environment_type: EnvironmentType
    labor_condition: LaborCondition

class ShiftCreate(BaseModel):
    location_id: uuid.UUID
    title: str
    description: str | None = None
    date: date
    start_time: time
    end_time: time
    max_volunteers: int

class ShiftRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    location_id: uuid.UUID
    title: str
    description: str | None
    date: date
    start_time: time
    end_time: time
    max_volunteers: int
    registered_count: int = 0

class RegistrationCreate(BaseModel):
    shift_id: uuid.UUID

class RegistrationRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    volunteer_id: uuid.UUID
    shift_id: uuid.UUID
    group_id: uuid.UUID | None
    status: RegistrationStatus
    checked_in_at: datetime | None
    created_at: datetime


# ─── Sprint 003 schemas ───────────────────────────────────
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


# ─── Sprint 004 schemas ───────────────────────────────────
class DiscoveryRequest(BaseModel):
    available_dates: list[date] = []
    preferred_environment: EnvironmentType | None = None
    preferred_labor_condition: LaborCondition | None = None
    location_ids: list[uuid.UUID] = []

class DiscoveryResult(BaseModel):
    shift_id: uuid.UUID
    score: float
    explanation: str


# ─── Sprint 005 schemas ───────────────────────────────────
class MessageRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    volunteer_id: uuid.UUID
    registration_id: uuid.UUID | None
    message_type: MessageType
    content: str
    status: MessageStatus
    sent_at: datetime | None
    created_at: datetime

class ImpactCardResponse(BaseModel):
    shift_title: str
    hours: float
    impact_metric: str

class NextCommitmentRequest(BaseModel):
    shift_id: uuid.UUID

class GivingInterestRequest(BaseModel):
    interested_in_monthly: bool
```

### `backend/app/auth.py`
```python
import uuid
from datetime import datetime, timedelta, timezone
from jose import JWTError, jwt
from app.config import get_settings
from app.exceptions import AppError, UNAUTHORIZED


def create_access_token(volunteer_id: uuid.UUID) -> str:
    settings = get_settings()
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.JWT_EXPIRE_MINUTES)
    payload = {"sub": str(volunteer_id), "exp": expire}
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def verify_token(token: str) -> dict:
    settings = get_settings()
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
    except JWTError:
        raise AppError(401, "Invalid or expired token", UNAUTHORIZED)
```

### `backend/app/dependencies.py`
```python
import uuid
from fastapi import Depends
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.auth import verify_token
from app.exceptions import AppError, UNAUTHORIZED, NOT_FOUND
from app.models import Volunteer


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/otp/verify", auto_error=False)


async def get_current_volunteer(
    token: str | None = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> Volunteer:
    if token is None:
        raise AppError(401, "Not authenticated", UNAUTHORIZED)
    payload = verify_token(token)
    sub = payload.get("sub")
    if sub is None:
        raise AppError(401, "Invalid token", UNAUTHORIZED)
    volunteer_id = uuid.UUID(sub)
    result = await db.execute(select(Volunteer).where(Volunteer.id == volunteer_id))
    volunteer = result.scalar_one_or_none()
    if volunteer is None:
        raise AppError(404, "Volunteer not found", NOT_FOUND)
    return volunteer
```

### `backend/app/main.py` — auto-discovering app factory (NEVER modified after this sprint)
```python
import importlib
import pkgutil
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from app.exceptions import AppError
from app import routers as routers_pkg


def create_app() -> FastAPI:
    app = FastAPI(title="NIFB Volunteer Portal", version="0.1.0")

    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"detail": exc.detail, "error_code": exc.error_code},
        )

    @app.get("/health")
    async def health():
        return {"status": "ok"}

    # Auto-discover and include every router file in app.routers/
    for _, modname, _ in pkgutil.iter_modules(routers_pkg.__path__):
        module = importlib.import_module(f"app.routers.{modname}")
        if hasattr(module, "router"):
            app.include_router(module.router)

    return app


app = create_app()
```

### `backend/app/routers/auth.py` — Sprint 001 feature
```python
import logging
import random
import string
import uuid
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.config import get_settings
from app.auth import create_access_token
from app.exceptions import AppError, ACCOUNT_EXISTS, INVALID_OTP, OTP_EXPIRED, NOT_FOUND
from app.models import Volunteer, OTP
from app.schemas import (
    OTPSendRequest, OTPSendResponse,
    OTPVerifyRequest, OTPVerifyResponse,
    RegisterRequest, RegisterResponse,
)


logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/otp/send", response_model=OTPSendResponse)
async def send_otp(req: OTPSendRequest, db: AsyncSession = Depends(get_db)):
    settings = get_settings()
    code = settings.OTP_BYPASS_CODE if settings.DEV_OTP_BYPASS else "".join(random.choices(string.digits, k=6))
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRY_MINUTES)
    db.add(OTP(phone=req.phone, code=code, expires_at=expires_at))
    await db.commit()
    logger.info(f"OTP for {req.phone}: {code}")
    return OTPSendResponse(message="OTP sent")


@router.post("/otp/verify", response_model=OTPVerifyResponse)
async def verify_otp(req: OTPVerifyRequest, db: AsyncSession = Depends(get_db)):
    settings = get_settings()
    bypass_ok = settings.DEV_OTP_BYPASS and req.code == settings.OTP_BYPASS_CODE
    if not bypass_ok:
        result = await db.execute(
            select(OTP)
            .where(OTP.phone == req.phone, OTP.code == req.code, OTP.used == False)
            .order_by(OTP.created_at.desc())
        )
        otp = result.scalars().first()
        if otp is None:
            raise AppError(401, "Invalid OTP code", INVALID_OTP)
        if otp.expires_at < datetime.now(timezone.utc):
            raise AppError(401, "OTP expired", OTP_EXPIRED)
        otp.used = True
        await db.commit()

    result = await db.execute(select(Volunteer).where(Volunteer.phone == req.phone))
    volunteer = result.scalar_one_or_none()
    if volunteer is None:
        return OTPVerifyResponse(access_token="", is_new=True, volunteer_id=uuid.uuid4())
    return OTPVerifyResponse(
        access_token=create_access_token(volunteer.id),
        is_new=False,
        volunteer_id=volunteer.id,
    )


@router.post("/register", response_model=RegisterResponse, status_code=201)
async def register(req: RegisterRequest, db: AsyncSession = Depends(get_db)):
    if req.email:
        existing = await db.execute(select(Volunteer).where(Volunteer.email == req.email))
        if existing.scalar_one_or_none():
            raise AppError(409, "Account with this email already exists", ACCOUNT_EXISTS)
    if req.phone:
        existing = await db.execute(select(Volunteer).where(Volunteer.phone == req.phone))
        if existing.scalar_one_or_none():
            raise AppError(409, "Account with this phone already exists", ACCOUNT_EXISTS)
    volunteer = Volunteer(
        email=req.email,
        phone=req.phone,
        first_name=req.first_name,
        last_name=req.last_name,
    )
    db.add(volunteer)
    await db.commit()
    await db.refresh(volunteer)
    return RegisterResponse(
        id=volunteer.id,
        email=volunteer.email,
        phone=volunteer.phone,
        access_token=create_access_token(volunteer.id),
    )
```

### `backend/scripts/init_db.py`
```python
import asyncio
from app.database import Base, get_engine


async def main():
    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


if __name__ == "__main__":
    asyncio.run(main())
```

## Imports per file

**`backend/app/__init__.py`** — empty

**`backend/app/config.py`**
```python
from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict
```

**`backend/app/database.py`**
```python
from collections.abc import AsyncGenerator
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from app.config import get_settings
```

**`backend/app/exceptions.py`**
```python
from fastapi import HTTPException
```

**`backend/app/models.py`**
```python
import enum
import uuid
from datetime import date, datetime, time
from sqlalchemy import ForeignKey, String, Text, Float, Boolean, DateTime, Integer, Date, Time
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import func
from app.database import Base
```

**`backend/app/schemas.py`**
```python
import uuid
from datetime import date, datetime, time
from pydantic import BaseModel, ConfigDict
from app.models import (
    RegistrationStatus, VolunteerPathway, MessageType, MessageStatus,
    EnvironmentType, LaborCondition, ReviewStatus,
)
```

**`backend/app/auth.py`**
```python
import uuid
from datetime import datetime, timedelta, timezone
from jose import JWTError, jwt
from app.config import get_settings
from app.exceptions import AppError, UNAUTHORIZED
```

**`backend/app/dependencies.py`**
```python
import uuid
from fastapi import Depends
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.auth import verify_token
from app.exceptions import AppError, UNAUTHORIZED, NOT_FOUND
from app.models import Volunteer
```

**`backend/app/main.py`**
```python
import importlib
import pkgutil
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from app.exceptions import AppError
from app import routers as routers_pkg
```

**`backend/app/routers/__init__.py`** — empty (load-bearing: pkgutil scans this directory)

**`backend/app/routers/auth.py`**
```python
import logging
import random
import string
import uuid
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.config import get_settings
from app.auth import create_access_token
from app.exceptions import AppError, ACCOUNT_EXISTS, INVALID_OTP, OTP_EXPIRED, NOT_FOUND
from app.models import Volunteer, OTP
from app.schemas import (
    OTPSendRequest, OTPSendResponse,
    OTPVerifyRequest, OTPVerifyResponse,
    RegisterRequest, RegisterResponse,
)
```

**`backend/app/services/__init__.py`** — empty

**`backend/scripts/init_db.py`**
```python
import asyncio
from app.database import Base, get_engine
```

**`backend/tests/__init__.py`** — empty

**`backend/tests/conftest.py`**
```python
import asyncio
import uuid
from collections.abc import AsyncGenerator
from datetime import date, datetime, time, timedelta, timezone
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from app.main import app
from app.database import Base
from app.dependencies import get_db
from app.models import (
    Volunteer, OTP, Location, Station, Shift, Registration, Group, GroupMember,
    WaiverAcceptance, OrientationCompletion, Message, GivingInterest,
    Assignment, SyncRecord, MatchException, SkillsApplication,
    CourtServiceRecord, BenefitsRecord,
    RegistrationStatus, VolunteerPathway, MessageType, MessageStatus,
    EnvironmentType, LaborCondition, ReviewStatus,
)
from app.auth import create_access_token
```

**`backend/tests/test_auth.py`**, **`backend/tests/test_health.py`**, **`backend/tests/test_config.py`**, **`backend/tests/test_models.py`**
```python
import pytest
import uuid
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import Volunteer, OTP
```

## Algorithm notes

### `backend/app/main.py` — pkgutil router auto-discovery
Copy this implementation exactly. Adding a router file in `app/routers/X.py` with a `router: APIRouter` attribute auto-registers it; main.py never needs modification.

```python
def create_app() -> FastAPI:
    app = FastAPI(title="NIFB Volunteer Portal", version="0.1.0")

    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"detail": exc.detail, "error_code": exc.error_code},
        )

    @app.get("/health")
    async def health():
        return {"status": "ok"}

    for _, modname, _ in pkgutil.iter_modules(routers_pkg.__path__):
        module = importlib.import_module(f"app.routers.{modname}")
        if hasattr(module, "router"):
            app.include_router(module.router)

    return app


app = create_app()
```

### `backend/tests/conftest.py` — full fixture suite for all sprints

```python
@pytest_asyncio.fixture
async def async_engine():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(async_engine) -> AsyncGenerator[AsyncSession, None]:
    factory = async_sessionmaker(async_engine, expire_on_commit=False)
    async with factory() as session:
        yield session


@pytest_asyncio.fixture
async def client(async_engine, db_session) -> AsyncGenerator[AsyncClient, None]:
    factory = async_sessionmaker(async_engine, expire_on_commit=False)

    async def override_get_db():
        async with factory() as s:
            yield s

    app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def test_volunteer(db_session) -> Volunteer:
    v = Volunteer(email="test@example.com", phone="+15551234567", first_name="Test", last_name="User")
    db_session.add(v)
    await db_session.commit()
    await db_session.refresh(v)
    return v


@pytest_asyncio.fixture
def auth_headers(test_volunteer) -> dict:
    return {"Authorization": f"Bearer {create_access_token(test_volunteer.id)}"}


@pytest_asyncio.fixture
async def test_location(db_session) -> Location:
    loc = Location(name="Main Warehouse", address="123 Test St")
    db_session.add(loc)
    await db_session.commit()
    await db_session.refresh(loc)
    return loc


@pytest_asyncio.fixture
async def test_station(db_session, test_location) -> Station:
    st = Station(
        location_id=test_location.id, name="Sorting", max_capacity=10,
        environment_type=EnvironmentType.indoor, labor_condition=LaborCondition.standing,
    )
    db_session.add(st)
    await db_session.commit()
    await db_session.refresh(st)
    return st


@pytest_asyncio.fixture
async def test_shift(db_session, test_location) -> Shift:
    sh = Shift(
        location_id=test_location.id, title="Saturday Morning", description="Sort and pack",
        date=date.today() + timedelta(days=1),
        start_time=time(9, 0), end_time=time(12, 0), max_volunteers=10,
    )
    db_session.add(sh)
    await db_session.commit()
    await db_session.refresh(sh)
    return sh
```

## Test plan

### `backend/tests/test_health.py`
```python
async def test_health_returns_ok(client: AsyncClient):
    r = await client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
```

### `backend/tests/test_config.py`
```python
def test_settings_defaults_load():
    from app.config import Settings
    s = Settings()
    assert s.DEV_OTP_BYPASS is True
    assert s.OTP_BYPASS_CODE == "000000"
    assert s.JWT_ALGORITHM == "HS256"
```

### `backend/tests/test_auth.py`
Subtests:
- `test_otp_send_returns_message` — POST /auth/otp/send returns 200 with {"message":"OTP sent"}
- `test_otp_verify_bypass_new_user` — POST /auth/otp/verify with code "000000" for unknown phone returns is_new=True
- `test_otp_verify_bypass_existing_user` — POST /auth/otp/verify with code "000000" for known phone returns access_token + is_new=False
- `test_register_creates_volunteer` — POST /auth/register with new email returns 201 with id, access_token
- `test_register_duplicate_email_returns_409` — second register with same email returns 409 with error_code="ACCOUNT_EXISTS"
- `test_register_duplicate_phone_returns_409` — second register with same phone returns 409 with error_code="ACCOUNT_EXISTS"
- `test_otp_verify_invalid_code_rejected` — with DEV_OTP_BYPASS=False, invalid code returns 401 INVALID_OTP

### `backend/tests/test_models.py` — foundation health check (every model must instantiate cleanly)
Subtests:
- `test_volunteer_create_persists` — Volunteer with email/phone persists, id is UUID
- `test_otp_create_persists` — OTP with phone+code+expires_at persists
- `test_location_and_station_relationship` — create Location, then Station with location_id; assert station.location loads
- `test_shift_with_registrations_relationship` — create Shift; create Registration with shift_id; assert shift.registrations contains it
- `test_group_with_members` — create Group, add 2 GroupMembers, assert group.members has both
- `test_message_persists_pending` — create Message with status=pending defaults
- `test_assignment_links_volunteer_station_shift` — create Assignment with all FK fields, assert relationships load
- `test_sync_record_persists` — SyncRecord created with sync_status="pending"
- `test_match_exception_persists` — MatchException with confidence_score, match_details (JSON string)
- `test_skills_application_persists` — SkillsApplication with resume_url, default review_status=pending
- `test_court_service_record_persists` — CourtServiceRecord with case_number, required_hours, default completed_hours=0.0
- `test_benefits_record_persists` — BenefitsRecord with program_type, required_hours

These are unit tests against the ORM only — no routes involved. They prove the schema is sound. Every later sprint trusts these models.

## Rules
- All sprint files MUST be written under `backend/`. Do NOT create files at workdir root.
- IDs are zero-padded 3-digit (001).
- `backend/app/routers/__init__.py` is intentionally empty — pkgutil discovery requires it to be a package.
- Internal imports use `from app.X import Y`, never `from backend.app.X import Y`.
- Tests use SQLite in-memory via `aiosqlite`; never connect to PostgreSQL during pytest.
- `pytest_asyncio` mode is `auto` per `[tool.pytest.ini_options]` in `pyproject.toml` — no `@pytest.mark.asyncio` decorator needed.
- The DEV_OTP_BYPASS=True default must be respected so tests can verify with code "000000".
- DO NOT modify `app/main.py`, `app/models.py`, `app/schemas.py`, `app/exceptions.py`, `app/database.py` in any later sprint. They are FROZEN after sprint 001.

## File contents (verbatim — for trivial files)

**`backend/app/__init__.py`** — empty file:
```python
```

**`backend/app/routers/__init__.py`** — empty file (load-bearing: pkgutil needs the package marker to exist so `routers_pkg.__path__` is populated):
```python
```

**`backend/app/services/__init__.py`** — empty file:
```python
```

**`backend/tests/__init__.py`** — empty file:
```python
```

**`backend/pyproject.toml`** — full manifest with every dep across all 16 sprints:
```toml
[project]
name = "nifb-backend"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.111.0",
    "uvicorn[standard]>=0.29.0",
    "sqlalchemy[asyncio]>=2.0.0",
    "asyncpg>=0.29.0",
    "aiosqlite>=0.20.0",
    "pydantic>=2.7.0",
    "pydantic-settings>=2.2.0",
    "python-jose[cryptography]>=3.3.0",
    "python-multipart>=0.0.9",
    "qrcode[pil]>=7.4.2",
    "Pillow>=10.0.0",
    "thefuzz>=0.22.1",
    "reportlab>=4.0.0",
    "httpx>=0.27.0",
]

[dependency-groups]
dev = [
    "pytest>=8.2.0",
    "pytest-asyncio>=0.23.0",
    "ruff>=0.4.0",
]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "I"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["app"]
```

## New files
- `backend/pyproject.toml` — full manifest with all 16-sprint dependencies + hatch wheel config
- `backend/app/__init__.py` — empty package marker
- `backend/app/config.py` — `Settings(BaseSettings)` with all env var fields
- `backend/app/database.py` — `Base`, async engine, `get_db` dependency
- `backend/app/exceptions.py` — `AppError` + every error code constant
- `backend/app/models.py` — every ORM model and enum across all 16 sprints (FROZEN after this sprint)
- `backend/app/schemas.py` — every Pydantic schema across all 16 sprints (FROZEN after this sprint)
- `backend/app/auth.py` — `create_access_token`, `verify_token`
- `backend/app/dependencies.py` — `oauth2_scheme`, `get_current_volunteer`
- `backend/app/main.py` — FastAPI app factory with pkgutil router auto-discovery (FROZEN after this sprint)
- `backend/app/routers/__init__.py` — empty package marker (load-bearing: pkgutil needs it)
- `backend/app/routers/auth.py` — Sprint 001 feature: OTP send/verify and register
- `backend/app/services/__init__.py` — empty package marker
- `backend/scripts/init_db.py` — async runner for `Base.metadata.create_all`
- `backend/tests/__init__.py` — empty package marker
- `backend/tests/conftest.py` — every fixture across all sprints
- `backend/tests/test_auth.py` — Sprint 001 feature tests (7 subtests)
- `backend/tests/test_health.py` — health endpoint smoke
- `backend/tests/test_config.py` — Settings defaults load
- `backend/tests/test_models.py` — foundation health check (12 model unit tests)

## Modified files
(none — this is the foundation sprint; nothing pre-exists)

## Expected Artifacts
- `backend/pyproject.toml`
- `backend/app/__init__.py`
- `backend/app/config.py`
- `backend/app/database.py`
- `backend/app/exceptions.py`
- `backend/app/models.py`
- `backend/app/schemas.py`
- `backend/app/auth.py`
- `backend/app/dependencies.py`
- `backend/app/main.py`
- `backend/app/routers/__init__.py`
- `backend/app/routers/auth.py`
- `backend/app/services/__init__.py`
- `backend/scripts/init_db.py`
- `backend/tests/__init__.py`
- `backend/tests/conftest.py`
- `backend/tests/test_auth.py`
- `backend/tests/test_health.py`
- `backend/tests/test_config.py`
- `backend/tests/test_models.py`

## DoD
- [ ] `cd backend && uv sync --all-extras` succeeds
- [ ] `cd backend && uv run pytest tests/test_health.py -v` passes
- [ ] `cd backend && uv run pytest tests/test_config.py -v` passes
- [ ] `cd backend && uv run pytest tests/test_auth.py -v` passes (7 subtests)
- [ ] `cd backend && uv run pytest tests/test_models.py -v` passes (12 subtests — proves ORM schema is sound for ALL future sprints)
- [ ] `cd backend && uv run ruff check app/ tests/` passes
- [ ] Total passing test count ≥ 21
- [ ] `app/main.py` uses pkgutil router auto-discovery (no hardcoded `include_router` calls)

## Validation
```bash
cd backend
uv sync --all-extras
uv run pytest -v
uv run ruff check app/ tests/
```
