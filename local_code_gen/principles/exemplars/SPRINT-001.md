# Sprint 001 — Foundation (full schema + auth, front-loaded)

## Scope
Front-load the entire backend foundation: every ORM model, every Pydantic schema, every shared error code, every test fixture, plus the FastAPI app factory with **auto-discovering router registration via `pkgutil`**. Implement the first feature (phone OTP authentication with JWT, register endpoint, `/health`) as the working slice. Subsequent sprints add only new router/service files — never modify `models.py`, `schemas.py`, `exceptions.py`, `database.py`, `config.py`, or `main.py`.

## Non-goals
- No frontend, Docker, CI.
- No SMS gateway integration — OTP is logged to console (Sprint 005 adds Twilio).
- No CRM sync, donor matching, skills, court, or benefits **logic** (Sprints 011–013) — but their MODELS and SCHEMAS are defined here so later sprints just import and use them.
- No Alembic migrations — `init_db.py` calls `Base.metadata.create_all`.

## Dependencies
None — first sprint, foundation.

## Conventions
- **Module:** `backend/app` package; internal imports as `from app.models import Volunteer` (NEVER `from backend.app.models import ...`).
- **Python:** 3.12+; package manager: `uv` with `pyproject.toml`.
- **Web:** `fastapi` + `uvicorn[standard]`.
- **ORM:** `sqlalchemy[asyncio]` 2.x with `AsyncSession`, `Mapped[...]` / `mapped_column(...)` style, `DeclarativeBase` subclass for `Base`. Test DB driver: `aiosqlite`. Production driver added in a later sprint when Postgres lands.
- **Validation:** `pydantic` v2 + `pydantic-settings`; ORM-shaped Read schemas use `model_config = ConfigDict(from_attributes=True)`.
- **Auth:** `python-jose[cryptography]` for JWT (HS256).
- **Tests:** `pytest` + `pytest-asyncio` (`asyncio_mode = "auto"` — do NOT add `@pytest.mark.asyncio` decorators) + `httpx.AsyncClient` with `ASGITransport`.
- **Lint:** `ruff` with rules `E`, `F`, `I` selected.
- **All IDs:** `uuid.UUID`, server-generated via `default=uuid.uuid4`.
- **All timestamps:** UTC `datetime` columns with `server_default=func.now()` (`onupdate=func.now()` on `updated_at`). Use `DateTime(timezone=True)`.
- **Errors:** Routers raise `AppError(status_code, detail, error_code)` (subclass of `HTTPException`). The app-level exception handler in `main.py` returns JSON `{"detail": "...", "error_code": "UPPER_SNAKE"}`. Tests assert `response.json()["error_code"]`.

## Tricky semantics (load-bearing — READ BEFORE WRITING ANY CODE)

These rules are **non-optional**. Each one closes an ambiguity that produces a runtime error which is hard to diagnose if you guess wrong. Tests are written assuming all of these hold.

1. **Settings singleton via `@lru_cache`.** `app/config.py` exposes `Settings(BaseSettings)` and a cached factory `get_settings() -> Settings`. Routers and helpers call `get_settings()` (which returns the cached instance) — never instantiate `Settings()` inside a request handler. Tests that need to verify defaults instantiate `Settings()` directly and read instance attributes.
2. **Database engine is lazy.** `app/database.py` does NOT call `create_async_engine` at module import time. Two module-level functions, `get_engine()` and `get_session_factory()`, lazily initialize on first call. This avoids "connect to Postgres at import time" failures when only tests are running.
3. **Async loading: `lazy="selectin"` on every collection-side relationship.** SQLAlchemy 2.x async sessions cannot lazy-load on attribute access — that raises `MissingGreenlet`. The collection-side relationships in this sprint that MUST have `lazy="selectin"` are: `Location.stations`, `Shift.registrations`, `Group.members`. Singular (many-to-one) sides like `Station.location`, `Registration.shift`, `GroupMember.group`, etc. do NOT need it.
4. **Bidirectional relationships use `back_populates` on BOTH sides** with matching names. Pairs in this sprint: `Location.stations` ↔ `Station.location`; `Shift.registrations` ↔ `Registration.shift`; `Group.members` ↔ `GroupMember.group`. Edit both sides together.
5. **Settings overrides in tests patch the instance, not the class.** Pydantic v2 stores fields on instances — `Settings.OTP_BYPASS_CODE` (class-attr) raises `AttributeError`. If a test needs to flip a flag, instantiate a fresh `Settings()` (env vars are re-read on each instantiation) and pass that, OR use `monkeypatch.setattr(get_settings(), "DEV_OTP_BYPASS", False)` against the live singleton.
6. **Tests use fixtures from `conftest.py`. ALWAYS take the fixture as a function parameter; NEVER construct `AsyncClient`, engines, sessions, or `app` instances inside test bodies.** `conftest.py` is the single point of test setup. Test files contain only test functions.
7. **Imports are complete Python statements, never bare module names.** When a class and a stdlib module share a name (`datetime`, `date`, `time`, `decimal.Decimal`), use the `from X import Y` form. Bare `datetime` reads as `import datetime` (the module) and breaks `Mapped[datetime]` annotations at SQLAlchemy mapping time.
8. **AppError is the only exception class routers raise.** Format: `raise AppError(status_code, detail_str, error_code_str)`. The handler in `main.py` formats the JSON response. Do not raise raw `HTTPException`; do not return `JSONResponse` from a route.
9. **Auto-discovering routers (load-bearing for front-loading).** `main.py` uses `pkgutil.iter_modules(routers_pkg.__path__)` to scan `app/routers/` and call `app.include_router(module.router)` for any module that exposes a `router: APIRouter`. **Later sprints add a new file in `app/routers/` and it is auto-included; `main.py` is FROZEN after this sprint.** Each router file declares its own `prefix` and `tags` on its `APIRouter()` instance.
10. **Test config constants are literal values.** When a test needs the OTP bypass code, write the literal string `"000000"` — not `Settings.OTP_BYPASS_CODE`, not `settings.OTP_BYPASS_CODE`.
11. **Use literal `pop(get_db, None)` in fixture cleanup, not `clear()`.** `app.dependency_overrides.clear()` would wipe overrides set by other tests/fixtures running concurrently or via composition. The `client` fixture cleans up only the override it set.

## Data contract

### Enums (declared in `app/models.py`)

```python
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
```

### ORM models (declared in `app/models.py`, FROZEN after this sprint)

All ids are `Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)`. All `created_at`/`updated_at` are `Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())` with `onupdate=func.now()` on `updated_at`. Indexed columns are noted explicitly.

```python
# Sprint 001 models
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

# Sprint 002 models — collection-side relationships use lazy="selectin"
class Location(Base):
    __tablename__ = "locations"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(200))
    address: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    stations: Mapped[list["Station"]] = relationship(back_populates="location", lazy="selectin")

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
    registrations: Mapped[list["Registration"]] = relationship(back_populates="shift", lazy="selectin")

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

# Sprint 003 models
class Group(Base):
    __tablename__ = "groups"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(200))
    leader_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    leader: Mapped["Volunteer"] = relationship()
    members: Mapped[list["GroupMember"]] = relationship(back_populates="group", lazy="selectin")

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

# Sprint 005 models
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

# Sprint 007 models
class Assignment(Base):
    __tablename__ = "assignments"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    volunteer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("volunteers.id"))
    station_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("stations.id"))
    shift_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("shifts.id"))
    is_manual_override: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

# Sprint 011 models
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

# Sprint 012 models
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

# Sprint 013 models
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

### Pydantic schemas (declared in `app/schemas.py`, FROZEN after this sprint)

All Read schemas use `model_config = ConfigDict(from_attributes=True)`.

```python
# Sprint 001
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

# Sprint 002
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

# Sprint 003
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

# Sprint 004
class DiscoveryRequest(BaseModel):
    available_dates: list[date] = []
    preferred_environment: EnvironmentType | None = None
    preferred_labor_condition: LaborCondition | None = None
    location_ids: list[uuid.UUID] = []

class DiscoveryResult(BaseModel):
    shift_id: uuid.UUID
    score: float
    explanation: str

# Sprint 005
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

## API contract (this sprint's routes)

The auth router declares `router = APIRouter(prefix="/auth", tags=["auth"])`. `/health` is mounted directly in `main.py` (not in a router, since no auth router file exists for it).

| Method | Path | Request | Response (status) | Errors |
|---|---|---|---|---|
| GET | `/health` | — | `{"status": "ok"}` (200) | — |
| POST | `/auth/otp/send` | `OTPSendRequest` | `OTPSendResponse{message="OTP sent"}` (200) | — |
| POST | `/auth/otp/verify` | `OTPVerifyRequest` | `OTPVerifyResponse` (200) | 401 `INVALID_OTP`, 401 `OTP_EXPIRED` |
| POST | `/auth/register` | `RegisterRequest` | `RegisterResponse` (201) | 409 `ACCOUNT_EXISTS` (duplicate email or phone) |

## Algorithm

### `POST /auth/otp/send`
1. Get settings via `get_settings()`.
2. If `settings.DEV_OTP_BYPASS` is True, set `code = settings.OTP_BYPASS_CODE`. Else generate 6 random digits via `"".join(random.choices(string.digits, k=6))`.
3. Compute `expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRY_MINUTES)`.
4. Insert `OTP(phone=req.phone, code=code, expires_at=expires_at)`; `await db.commit()`.
5. `logger.info(f"OTP for {req.phone}: {code}")`.
6. Return `OTPSendResponse(message="OTP sent")`.

### `POST /auth/otp/verify`
1. Get settings. `bypass_ok = settings.DEV_OTP_BYPASS and req.code == settings.OTP_BYPASS_CODE`.
2. If NOT bypass_ok: query `OTP` where `phone == req.phone AND code == req.code AND used == False`, ordered by `created_at desc`. If no row → `raise AppError(401, "Invalid OTP code", INVALID_OTP)`. If `expires_at < now()` → `raise AppError(401, "OTP expired", OTP_EXPIRED)`. Else mark `otp.used = True` and `await db.commit()`.
3. Find existing `Volunteer` by phone. If none, return `OTPVerifyResponse(access_token="", is_new=True, volunteer_id=uuid.uuid4())` (caller must hit `/auth/register` next; the throwaway uuid is so the response shape is consistent — the real id is created by register).
4. If found: return `OTPVerifyResponse(access_token=create_access_token(volunteer.id), is_new=False, volunteer_id=volunteer.id)`.

### `POST /auth/register`
1. If `req.email` is provided, check for existing volunteer by email — if found, raise `AppError(409, "Account with this email already exists", ACCOUNT_EXISTS)`.
2. If `req.phone` is provided, check for existing volunteer by phone — if found, raise `AppError(409, "Account with this phone already exists", ACCOUNT_EXISTS)`.
3. Insert `Volunteer(email, phone, first_name, last_name)`; commit; refresh.
4. Return `RegisterResponse(id, email, phone, access_token=create_access_token(volunteer.id))` with status 201.

### `GET /health`
1. Return `{"status": "ok"}`.

## Test contract

### `tests/conftest.py` fixtures

All fixtures are function-scoped (no `@pytest_asyncio.fixture(scope="...")` argument needed; default is function-scope under `asyncio_mode = "auto"`).

- **`async_engine`** — creates `create_async_engine("sqlite+aiosqlite:///:memory:", echo=False, connect_args={"check_same_thread": False}, poolclass=StaticPool)`, runs `Base.metadata.create_all`, yields the engine, calls `await engine.dispose()` on cleanup. **`StaticPool` and `connect_args` are non-optional**: SQLite's `:memory:` URL gives every fresh connection its own database. Without `StaticPool`, the `client` fixture's override session and the `db_session` fixture end up on different in-memory DBs, and tests that commit via one session and read via the other observe nothing. Imports needed: `from sqlalchemy.pool import StaticPool`.
- **`db_session(async_engine)`** — yields an `AsyncSession` from `async_sessionmaker(async_engine, expire_on_commit=False)`.
- **`client(async_engine, db_session)`** — Inside the fixture body (NOT at module level): build `factory = async_sessionmaker(async_engine, expire_on_commit=False)`; define a **nested closure** `async def override_get_db():\n    async with factory() as s:\n        yield s`; register `app.dependency_overrides[get_db] = override_get_db`; construct `AsyncClient(transport=ASGITransport(app=app), base_url="http://test")`; yield the client; on cleanup call `app.dependency_overrides.pop(get_db, None)`.

  **Critical:** `override_get_db` MUST be defined inside the `client` fixture function so it captures `async_engine` via closure. If it is defined at module level, `async_engine` resolves to the pytest-fixture function reference (a `FixtureFunctionDefinition` object), not the resolved engine instance, and `async_sessionmaker(async_engine, ...)` raises `sqlalchemy.exc.ArgumentError: AsyncEngine expected, got <pytest_fixture(...)>`.

  Imports `app` from `app.main` and `get_db` from `app.dependencies`.
- **`test_volunteer(db_session)`** — creates `Volunteer(email="test@example.com", phone="+15551234567", first_name="Test", last_name="User")`, commits, refreshes, returns it.
- **`auth_headers(test_volunteer)`** — synchronous function returning `{"Authorization": f"Bearer {create_access_token(test_volunteer.id)}"}`.
- **`test_location(db_session)`** — creates `Location(name="Main Warehouse", address="123 Test St")`, commits, refreshes, returns it.
- **`test_station(db_session, test_location)`** — creates `Station(location_id=test_location.id, name="Sorting", max_capacity=10, environment_type=EnvironmentType.indoor, labor_condition=LaborCondition.standing)`, commits, refreshes, returns it.
- **`test_shift(db_session, test_location)`** — creates `Shift(location_id=test_location.id, title="Saturday Morning", description="Sort and pack", date=date.today() + timedelta(days=1), start_time=time(9, 0), end_time=time(12, 0), max_volunteers=10)`, commits, refreshes, returns it.

### `tests/test_health.py`

| Test | Action | Asserts |
|---|---|---|
| `test_health_returns_ok(client)` | `GET /health` | 200, `body == {"status": "ok"}` |

### `tests/test_config.py`

| Test | Action | Asserts |
|---|---|---|
| `test_settings_defaults_load()` | Instantiate `Settings()` | `s.DEV_OTP_BYPASS is True`, `s.OTP_BYPASS_CODE == "000000"`, `s.JWT_ALGORITHM == "HS256"` |

### `tests/test_auth.py` (7 subtests)

All tests take `client` (from conftest) as a parameter; some additionally take `db_session` or other fixtures. The OTP bypass code is the literal string `"000000"`.

| Test | Action | Asserts |
|---|---|---|
| `test_otp_send_returns_message(client)` | POST `/auth/otp/send` `{"phone": "+15550000001"}` | 200, `body["message"] == "OTP sent"` |
| `test_otp_verify_bypass_new_user(client)` | POST `/auth/otp/verify` `{"phone": "+15550000002", "code": "000000"}` | 200, `body["is_new"] is True` |
| `test_otp_verify_bypass_existing_user(client, test_volunteer)` | POST `/auth/otp/verify` `{"phone": test_volunteer.phone, "code": "000000"}` | 200, `body["is_new"] is False`, `body["access_token"]` non-empty |
| `test_register_creates_volunteer(client)` | POST `/auth/register` `{"phone":"+15550000003","email":"a@b.com","first_name":"A","last_name":"B"}` | 201, `body["id"]` present, `body["access_token"]` non-empty |
| `test_register_duplicate_email_returns_409(client)` | Register once with email `dup@example.com`; then again with same email and different phone | 409, `body["error_code"] == "ACCOUNT_EXISTS"` |
| `test_register_duplicate_phone_returns_409(client)` | Register once with phone `+15550000004`; then again with same phone and different email | 409, `body["error_code"] == "ACCOUNT_EXISTS"` |
| `test_otp_verify_invalid_code_rejected(client, monkeypatch)` | `monkeypatch.setattr(get_settings(), "DEV_OTP_BYPASS", False)`; POST `/auth/otp/verify` `{"phone": "+15550000005", "code": "999999"}` | 401, `body["error_code"] == "INVALID_OTP"` |

### `tests/test_models.py` (12 subtests — foundation health check)

ORM-only; no HTTP. Each test creates an instance via `db_session`, commits, queries it back (via `select`), and asserts persistence + relationship loading where applicable.

| Test | Action | Asserts |
|---|---|---|
| `test_volunteer_create_persists(db_session)` | Create + commit a `Volunteer`; reload via select | id is `uuid.UUID`, email/phone match |
| `test_otp_create_persists(db_session)` | Create + commit an `OTP` | record persisted, `used is False` |
| `test_location_and_station_relationship(db_session)` | Create Location, then Station with `location_id`; reload Station | `station.location.name` matches |
| `test_shift_with_registrations_relationship(db_session, test_volunteer)` | Create Location, Shift, Registration; reload Shift | `len(shift.registrations) == 1` (relies on `lazy="selectin"`) |
| `test_group_with_members(db_session, test_volunteer)` | Create Group with `leader_id`, two `GroupMember`s; reload Group | `len(group.members) == 2` (relies on `lazy="selectin"`) |
| `test_message_persists_pending(db_session, test_volunteer)` | Create `Message(volunteer_id, message_type=confirmation, content="hi")` | `status is MessageStatus.pending` (default) |
| `test_assignment_links_volunteer_station_shift(db_session, test_volunteer, test_station, test_shift)` | Create `Assignment` with all 3 FK fields | record persisted, FKs match |
| `test_sync_record_persists(db_session, test_volunteer)` | Create `SyncRecord(volunteer_id, sync_status="pending")` | persisted, `synced_at is None` |
| `test_match_exception_persists(db_session, test_volunteer)` | Create `MatchException(volunteer_id, confidence_score=0.85, match_details="{...}")` | persisted, `resolved is False` |
| `test_skills_application_persists(db_session, test_volunteer)` | Create `SkillsApplication(volunteer_id, resume_url="https://...")` | persisted, `review_status is ReviewStatus.pending` |
| `test_court_service_record_persists(db_session, test_volunteer)` | Create `CourtServiceRecord(volunteer_id, case_number="C-123", required_hours=20.0)` | persisted, `completed_hours == 0.0` |
| `test_benefits_record_persists(db_session, test_volunteer)` | Create `BenefitsRecord(volunteer_id, program_type="SNAP", required_hours=80.0)` | persisted, `completed_hours == 0.0` |

## Verbatim files (small files where exact text matters more than logic)

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

### `backend/app/main.py` (FROZEN after this sprint — auto-discovery is load-bearing)

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

### `backend/app/database.py` (lazy engine init — avoids import-time DB connect)

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

### `backend/pyproject.toml`

```toml
[project]
name = "nifb-backend"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.111.0",
    "uvicorn[standard]>=0.29.0",
    "sqlalchemy[asyncio]>=2.0.0",
    "aiosqlite>=0.20.0",
    "pydantic>=2.7.0",
    "pydantic-settings>=2.2.0",
    "python-jose[cryptography]>=3.3.0",
    "httpx>=0.27.0",
]

[project.optional-dependencies]
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

> **Build-system note (load-bearing).** `[tool.hatch.build.targets.wheel] packages = ["app"]` is mandatory — the project name (`nifb-backend`) does not match the package directory (`app`), so hatchling auto-detection fails without it. Omitting this block crashes `uv sync` before any test runs.

> **Deps note.** Only deps actually used in this sprint are listed. Sprints that introduce new deps (e.g., Sprint 005's `qrcode[pil]`, Sprint 011's CRM SDK) MUST modify `pyproject.toml` to add them — that's the one explicit modification a non-foundation sprint may make. They append to `dependencies` (or `dev`) only; no other section.

## New files
- `backend/pyproject.toml` — verbatim from "Verbatim files" section.
- `backend/app/__init__.py` — empty package marker.
- `backend/app/config.py` — verbatim from "Verbatim files" section.
- `backend/app/database.py` — verbatim from "Verbatim files" section (lazy engine init).
- `backend/app/exceptions.py` — verbatim from "Verbatim files" section (AppError + 17 error code constants).
- `backend/app/models.py` — every enum + every ORM model from "Data contract → Enums" and "ORM models" sections, in the listed order. Imports (use these EXACT statements): `import enum`, `import uuid`, `from datetime import date, datetime, time`, `from sqlalchemy import ForeignKey, String, Text, DateTime, func`, `from sqlalchemy.orm import Mapped, mapped_column, relationship`, `from app.database import Base`. No other imports. FROZEN after this sprint.
- `backend/app/schemas.py` — every Pydantic schema from "Data contract → Pydantic schemas" section. Imports: `import uuid`, `from datetime import date, datetime, time`, `from pydantic import BaseModel, ConfigDict`, `from app.models import RegistrationStatus, VolunteerPathway, MessageType, MessageStatus, EnvironmentType, LaborCondition, ReviewStatus`. FROZEN after this sprint.
- `backend/app/auth.py` — `create_access_token(volunteer_id: uuid.UUID) -> str` and `verify_token(token: str) -> dict`. Token payload `{"sub": str(volunteer_id), "exp": <utc datetime>}`. Uses `get_settings().SECRET_KEY` and `get_settings().JWT_ALGORITHM`. On `JWTError` → `raise AppError(401, "Invalid or expired token", UNAUTHORIZED)`. Imports: `import uuid`, `from datetime import datetime, timedelta, timezone`, `from jose import JWTError, jwt`, `from app.config import get_settings`, `from app.exceptions import AppError, UNAUTHORIZED`.
- `backend/app/dependencies.py` — `oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/otp/verify", auto_error=False)` and `async def get_current_volunteer(token: str | None = Depends(oauth2_scheme), db: AsyncSession = Depends(get_db)) -> Volunteer` that decodes the token, looks up the volunteer by `uuid.UUID(payload["sub"])`, and raises `AppError(401, ..., UNAUTHORIZED)` on missing token / `AppError(404, ..., NOT_FOUND)` on missing volunteer. Imports: `import uuid`, `from fastapi import Depends`, `from fastapi.security import OAuth2PasswordBearer`, `from sqlalchemy import select`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.database import get_db`, `from app.auth import verify_token`, `from app.exceptions import AppError, UNAUTHORIZED, NOT_FOUND`, `from app.models import Volunteer`.
- `backend/app/main.py` — verbatim from "Verbatim files" section (auto-discovery). FROZEN after this sprint.
- `backend/app/routers/__init__.py` — empty package marker (load-bearing: pkgutil scans this directory).
- `backend/app/routers/auth.py` — `router = APIRouter(prefix="/auth", tags=["auth"])` plus the three POST handlers per "Algorithm" section. Imports: `import logging`, `import random`, `import string`, `import uuid`, `from datetime import datetime, timedelta, timezone`, `from fastapi import APIRouter, Depends`, `from sqlalchemy import select`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.database import get_db`, `from app.config import get_settings`, `from app.auth import create_access_token`, `from app.exceptions import AppError, ACCOUNT_EXISTS, INVALID_OTP, OTP_EXPIRED`, `from app.models import Volunteer, OTP`, `from app.schemas import OTPSendRequest, OTPSendResponse, OTPVerifyRequest, OTPVerifyResponse, RegisterRequest, RegisterResponse`. Uses `logger = logging.getLogger(__name__)`.
- `backend/app/services/__init__.py` — empty package marker (later sprints add service files here).
- `backend/scripts/init_db.py` — verbatim from "Verbatim files" section.
- `backend/tests/__init__.py` — empty package marker.
- `backend/tests/conftest.py` — fixtures per "Test contract → conftest.py fixtures" section. Imports: `import asyncio`, `import uuid`, `from collections.abc import AsyncGenerator`, `from datetime import date, datetime, time, timedelta, timezone`, `import pytest`, `import pytest_asyncio`, `from httpx import ASGITransport, AsyncClient`, `from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine`, `from sqlalchemy.pool import StaticPool`, `from app.main import app`, `from app.database import Base`, `from app.dependencies import get_db`, `from app.models import (Volunteer, OTP, Location, Station, Shift, Registration, Group, GroupMember, WaiverAcceptance, OrientationCompletion, Message, GivingInterest, Assignment, SyncRecord, MatchException, SkillsApplication, CourtServiceRecord, BenefitsRecord, RegistrationStatus, VolunteerPathway, MessageType, MessageStatus, EnvironmentType, LaborCondition, ReviewStatus)`, `from app.auth import create_access_token`.
- `backend/tests/test_health.py` — single test per "Test contract → test_health.py" table. Imports: `from httpx import AsyncClient`. Uses `client: AsyncClient` fixture parameter (annotation makes the import non-unused).
- `backend/tests/test_config.py` — single test per "Test contract → test_config.py" table. Imports: `from app.config import Settings`. No async, no fixtures used.
- `backend/tests/test_auth.py` — 7 tests per "Test contract → test_auth.py" table. Imports: `from httpx import AsyncClient`, `from app.config import get_settings`. Uses `client: AsyncClient`, `test_volunteer`, `monkeypatch` fixture parameters (annotation makes the AsyncClient import non-unused).
- `backend/tests/test_models.py` — 12 tests per "Test contract → test_models.py" table. Imports: `import uuid`, `from datetime import date, datetime, time, timedelta, timezone`, `from sqlalchemy import select`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.models import (Volunteer, OTP, Location, Station, Shift, Registration, Group, GroupMember, Message, MessageStatus, MessageType, Assignment, SyncRecord, MatchException, SkillsApplication, ReviewStatus, CourtServiceRecord, BenefitsRecord, EnvironmentType, LaborCondition)`. Uses `db_session`, `test_volunteer`, `test_station`, `test_shift` fixtures.

## Modified files
(none — foundation sprint)

## Rules
- **FROZEN files (no later sprint may modify these):** `app/main.py`, `app/models.py`, `app/schemas.py`, `app/exceptions.py`, `app/database.py`, `app/config.py`. The only foundation file later sprints may modify is `pyproject.toml`, and only to append new dependencies under `[project.dependencies]` or `[project.optional-dependencies]`.
- All sprint files MUST be written under `backend/`. Do NOT create files at workdir root.
- All file imports must be the minimum used (`ruff` will fail F401 on unused imports).
- Imports are written as **complete Python statements**, never bare module names. When a class and a stdlib module share a name (`datetime`, `date`, `time`, `decimal.Decimal`), use `from X import Y` form. Bare `datetime` would import the module and break `Mapped[datetime]` annotations at SQLAlchemy mapping time.
- Tests take fixtures (`client`, `db_session`, `test_volunteer`, etc.) as **function parameters** — never construct `AsyncClient`, engines, or sessions inside test bodies. The fixture system in `conftest.py` is the single point of test setup; per-test self-sufficiency is forbidden.
- Tests use literal string values for config-derived constants. The OTP bypass code is `"000000"` (literal string) wherever it appears in tests — never `Settings.OTP_BYPASS_CODE` (Pydantic v2 raises `AttributeError` on class-attr access of a field).
- All test functions are `async def` (except `test_settings_defaults_load`, which is sync). Do NOT add `@pytest.mark.asyncio` decorators (`asyncio_mode = "auto"` handles them; the decorator is redundant and may emit deprecation warnings).
- `Base` is declared exactly once — in `app/database.py` as `class Base(DeclarativeBase): pass`. Models import it; no other module redeclares it.
- Routers expose their `APIRouter` instance as the module-level name `router`. `main.py`'s pkgutil discovery requires this exact attribute name.
- `app/main.py` calls `create_app()` at module level so `app` is importable for tests as `from app.main import app`.
- The OTP `code` is logged but never returned in any response. Only the bypass code (`"000000"`) lets a test verify without reading the log.
- `app.dependency_overrides.pop(get_db, None)` (NOT `clear()`) on `client` fixture teardown.
- **Fixture-dependent helpers must be closures INSIDE the consuming fixture.** When a helper function (e.g., `override_get_db`) references a value that comes from another fixture (e.g., `async_engine`), the helper must be a nested `async def` inside the fixture function so it captures the resolved parameter via closure. Defining the helper at module level binds the name to the fixture's decorator object (a `FixtureFunctionDefinition`), not the resolved value, and runtime call-sites get the wrong type.
- Internal imports use `from app.X import Y`, never `from backend.app.X import Y`.
- The DEV_OTP_BYPASS=True default must be respected so most tests can verify with code "000000". The single test that exercises a non-bypass path uses `monkeypatch.setattr(get_settings(), "DEV_OTP_BYPASS", False)`.

## DoD
- [ ] `cd backend && uv sync --all-extras` exits 0.
- [ ] `cd backend && uv run pytest tests/test_health.py -v` passes (1 test).
- [ ] `cd backend && uv run pytest tests/test_config.py -v` passes (1 test).
- [ ] `cd backend && uv run pytest tests/test_auth.py -v` passes (7 tests).
- [ ] `cd backend && uv run pytest tests/test_models.py -v` passes (12 tests — proves ORM schema is sound for ALL future sprints).
- [ ] `cd backend && uv run pytest -v` cumulative ≥ 21 tests passing.
- [ ] `cd backend && uv run ruff check app/ tests/` exits 0 with no errors.
- [ ] `app/main.py` uses `pkgutil.iter_modules(routers_pkg.__path__)` for router discovery — no hardcoded `app.include_router(auth_router)` calls.
- [ ] All ORM models import without error: `cd backend && uv run python -c "from app.models import Volunteer, OTP, Location, Station, Shift, Registration, Group, GroupMember, WaiverAcceptance, OrientationCompletion, Message, GivingInterest, Assignment, SyncRecord, MatchException, SkillsApplication, CourtServiceRecord, BenefitsRecord"`.

## Validation
```bash
cd backend
uv sync --all-extras
uv run pytest -v
uv run ruff check app/ tests/
```
