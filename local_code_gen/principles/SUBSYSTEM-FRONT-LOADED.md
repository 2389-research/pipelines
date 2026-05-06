# Subsystem-front-loaded architecture

The pattern for projects too large to fit a single front-loaded foundation sprint. Each sprint front-loads its OWN subsystem (models, schemas, services, tests for that subsystem) as new files; auto-discovery for both routers AND models means later sprints don't modify any earlier-sprint file.

A sibling pattern to [`ARCHITECT-V2-DESIGN.md`](ARCHITECT-V2-DESIGN.md)'s all-front-loaded approach. Pick the right one per project — **see decision criteria below**.

## Why this pattern exists

The all-front-loaded approach (`ARCHITECT-V2-DESIGN.md`) declares every ORM model + every Pydantic schema in sprint 001. For small projects (3-7 entities) this is fine — sprint 001 is ~600 lines of spec, fits comfortably under any sane LLM output cap.

For larger projects it breaks down. NIFB has **18 ORM models + 25 Pydantic schemas + JWT auth + OTP flow + full conftest + 18 tests across 3 test files**. The architect on May 1 emitted 1068-line / 53KB SPRINT-001.md spec with the all-front-loaded pattern — and even that **truncated mid-Rules section** because Sonnet hit the 8K output-token cap before reaching `## DoD` and `## Validation`. Bumping `MaxTokens` to 16K is a band-aid; the deeper issue is that "everything in sprint 001" is the wrong abstraction for projects of NIFB's scale.

The architect-grade fix: front-load BY SUBSYSTEM. Each sprint owns its subsystem completely; cross-sprint deps go through clean module imports.

## When to use which pattern

Use the existing **all-front-loaded** pattern (`ARCHITECT-V2-DESIGN.md`) when:

- Project has ≤ 7 ORM entities total
- Sprint plan has ≤ 4 sprints
- Sprint 001 spec is projected to fit in ~600-700 lines
- Data model is small enough that one foundation sprint can declare it cleanly

Use **subsystem-front-loaded** (this doc) when ANY of:

- Project has ≥ 8 ORM entities, OR
- Sprint plan has ≥ 5 sprints, OR
- Foundation sprint would exceed ~700 lines of spec, OR
- The sprint plan already decomposes work along subsystem boundaries (auth, operations, groups, messaging, etc.)

The middle ground (5-7 entities, 4-5 sprints) — either works. Pick subsystem-front-loaded if the sprint plan reads as subsystems; pick all-front-loaded if the data model is highly interconnected and "subsystems" don't carve cleanly.

The architect should make this call from the spec_analysis + sprint_plan inputs and declare the choice explicitly in `contract.md`'s Architectural Pattern section.

## The pattern

### File structure

```text
backend/
  pyproject.toml                    — sprint 001; modifiable (later sprints append deps)
  app/
    __init__.py                     — empty package marker; FROZEN sprint 001
    main.py                         — auto-discovery for both routers AND models; FROZEN sprint 001
    config.py                       — Settings + get_settings(); FROZEN sprint 001
    database.py                     — Base, lazy engine, get_db; FROZEN sprint 001
    exceptions.py                   — AppError + ALL error code constants used across sprints; FROZEN sprint 001
    auth.py                         — JWT helpers; FROZEN sprint 001 (or sprint that introduces auth)
    dependencies.py                 — re-exports + get_current_user; FROZEN sprint 001
    models/
      __init__.py                   — pkgutil auto-import; FROZEN sprint 001
      auth.py                       — Volunteer, OTP (sprint 001's subsystem); FROZEN sprint 001
      operations.py                 — Location, Station, Shift, Registration; FROZEN sprint 002
      groups.py                     — Group, GroupMember, WaiverAcceptance, OrientationCompletion; FROZEN sprint 003
      ...                            — one module per subsystem
    schemas/
      __init__.py                   — empty (no auto-discovery needed; explicit imports)
      auth.py                       — UserCreate, UserRead, OTP*Request, etc.; FROZEN sprint 001
      operations.py                 — sprint 002
      ...
    routers/
      __init__.py                   — empty package marker
      health.py                     — sprint 001
      auth.py                       — sprint 001
      operations.py                 — sprint 002 (CRUD for the sprint-002 entities)
      groups.py                     — sprint 003
      ...
  tests/
    __init__.py                     — empty package marker
    conftest.py                     — base fixtures + per-subsystem fixtures appended; load-bearing; sprint 001 owns base, later sprints append fixtures by ADDING NEW FIXTURE FILES (see below)
    fixtures/                       — per-subsystem fixture modules (auto-discovered by conftest)
      __init__.py
      auth.py                       — test_volunteer, auth_headers; sprint 001
      operations.py                 — test_location, test_shift; sprint 002
      ...
    test_health.py                  — sprint 001
    test_auth.py                    — sprint 001
    test_operations.py              — sprint 002
    test_groups.py                  — sprint 003
    ...
```

### Auto-discovery for models (load-bearing)

The pattern's correctness depends on `app/models/__init__.py` importing every submodule before SQLAlchemy's `Base.metadata.create_all` runs. Without that, classes defined in submodules aren't registered with `Base.metadata` and the test database will be missing those tables.

```python
# app/models/__init__.py — FROZEN sprint 001
"""Auto-discover and import every model submodule.

Each submodule defines ORM classes via `class X(Base): ...`. The act of
importing the module registers those classes with `Base.metadata`. Doing this
in __init__ ensures `from app.models import Base` (or any model class) gives
you a fully-populated metadata.
"""
import importlib
import pkgutil

# Re-export Base for convenience
from app.database import Base as Base  # noqa: F401

# Import every submodule so its model classes register with Base.metadata
for _, modname, _ in pkgutil.iter_modules(__path__):
    importlib.import_module(f"{__name__}.{modname}")
```

Each per-subsystem module declares its ORM classes against the shared `Base`:

```python
# app/models/operations.py — FROZEN sprint 002
import uuid
from datetime import datetime
from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Location(Base):
    __tablename__ = "locations"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(200))
    # ...
    shifts: Mapped[list["Shift"]] = relationship("Shift", back_populates="location", lazy="selectin")


class Station(Base):
    __tablename__ = "stations"
    # ...
```

### Auto-discovery for fixtures (optional but recommended)

For per-subsystem test fixtures, mirror the pattern. A small `conftest.py` does:

```python
# tests/conftest.py — FROZEN sprint 001
"""Auto-import every per-subsystem fixture module.

pytest discovers fixtures from any module imported into conftest scope. Doing
the auto-import here means later sprints just drop a new file in
`tests/fixtures/<subsystem>.py` and pytest finds the new fixtures.
"""
import importlib
import pkgutil

from tests import fixtures as fixtures_pkg

for _, modname, _ in pkgutil.iter_modules(fixtures_pkg.__path__):
    module = importlib.import_module(f"{fixtures_pkg.__name__}.{modname}")
    # Re-export every public name so pytest finds the fixtures
    for name in dir(module):
        if not name.startswith("_"):
            globals()[name] = getattr(module, name)


# Base fixtures (engine, session, client) live here directly because they
# don't belong to any one subsystem.
# ... async_engine, db_session, client, etc.
```

This is more complex than the routers/models case because pytest's fixture discovery doesn't follow Python's normal import graph; you have to re-export to conftest's namespace. **If this seems fragile, the simpler alternative is: foundation sprint owns the entire conftest, and per-sprint fixtures live in their own test files** (since pytest discovers fixtures from any conftest.py and from within a test module). Choose based on whether per-subsystem fixture isolation is worth the extra discovery layer.

### Cross-sprint dependencies

Sprint 002 needing `Volunteer` and `Registration` does:

```python
# app/routers/operations.py — sprint 002
from app.models.auth import Volunteer
from app.models.operations import Location, Station, Shift, Registration
from app.schemas.auth import VolunteerRead
from app.schemas.operations import LocationRead, ShiftRead, RegistrationRead, RegistrationCreate
from app.dependencies import get_current_user
```

Type-name uniqueness across the whole project is still a contract.md concern (the Type/Symbol Ownership Map declares which sprint introduces which type). That doesn't change.

### Bidirectional relationships across subsystem modules

`Volunteer.registrations` lives in `app/models/auth.py` (sprint 001 doesn't define it; gets defined when sprint 002 introduces `Registration`). This is the one tricky case:

**Option A: Volunteer pre-declares the relationship as a forward reference**

```python
# app/models/auth.py — sprint 001
class Volunteer(Base):
    # ...
    # Forward-declared relationships to be wired by later subsystems:
    registrations: Mapped[list["Registration"]] = relationship(
        "Registration", back_populates="volunteer", lazy="selectin"
    )
    waiver_acceptances: Mapped[list["WaiverAcceptance"]] = relationship(
        "WaiverAcceptance", back_populates="volunteer", lazy="selectin"
    )
```

Sprint 001 defines the forward references using string class names. SQLAlchemy resolves them lazily when both sides exist. Sprint 002's `Registration.volunteer` and sprint 003's `WaiverAcceptance.volunteer` complete the pair.

**Option B: Each later sprint extends Volunteer via class-relationship-after-the-fact**

Less clean; SQLAlchemy supports it but the `relationship()` call has to happen after both classes are imported. Not recommended.

**Recommendation: Option A.** Forward-declare cross-subsystem relationships in the OWNER class's module, with string class names. The cross-sprint Type Ownership Map in contract.md must declare these forward references explicitly so each later sprint knows it's expected.

This means sprint 001's `app/models/auth.py` is bigger than just "Volunteer + OTP" — it includes the forward-declarations for cross-subsystem relationships. But the forward declarations are tiny (~5 lines per relationship pair); the sprint stays compact.

## Per-sprint contract.md changes

Two sections in `contract.md` change shape under this pattern:

### Sprint File-Ownership Map

Each sprint owns a fixed set of NEW files; no sprint after sprint 001 has any `## Modified files` entry.

```text
Sprint 001 (foundation + auth subsystem):
  NEW: app/__init__.py, app/main.py, app/config.py, app/database.py,
       app/exceptions.py, app/auth.py, app/dependencies.py,
       app/models/__init__.py, app/models/auth.py,
       app/schemas/__init__.py, app/schemas/auth.py,
       app/routers/__init__.py, app/routers/health.py, app/routers/auth.py,
       scripts/init_db.py,
       tests/__init__.py, tests/conftest.py, tests/fixtures/__init__.py,
       tests/fixtures/auth.py, tests/test_health.py, tests/test_auth.py,
       tests/test_models.py, tests/test_config.py
       pyproject.toml
  FROZEN after: ALL of the above except pyproject.toml

Sprint 002 (operations subsystem):
  NEW: app/models/operations.py, app/schemas/operations.py,
       app/routers/operations.py, tests/fixtures/operations.py,
       tests/test_operations.py
  MODIFIED: (none — auto-discovery picks up models, schemas, routers, fixtures)

Sprint 003 (groups + waivers subsystem):
  NEW: app/models/groups.py, app/schemas/groups.py,
       app/routers/groups.py, tests/fixtures/groups.py,
       tests/test_groups.py
  MODIFIED: (none)

...
```

### Cross-Sprint Type/Symbol Ownership Map

For each model class, declare:
- The owning sprint
- The owning module (`app/models/<subsystem>.py`)
- The exact field signatures
- For collection-side relationships: `lazy="selectin"`
- For bidirectional relationships: `back_populates` on BOTH sides AND **which side defines the forward reference** (always the side from the earlier sprint)

This map is bigger than under all-front-loaded because it lists per-module ownership. But it's the same total information; just organized by-subsystem instead of by-class.

## Updated foundation main.py

The auto-discovery in `main.py` mostly stays the same as `ARCHITECT-V2-DESIGN.md`, but it now also has to ensure `app.models` is fully imported before any DB-touching code runs:

```python
# app/main.py — FROZEN sprint 001
import importlib
import pkgutil

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

# Importing app.models triggers its __init__.py auto-discovery,
# which imports every per-subsystem model module.
import app.models  # noqa: F401  — registers all model classes with Base.metadata

from app.exceptions import AppError
from app import routers as routers_pkg


def create_app() -> FastAPI:
    app = FastAPI(title="<Project>", version="0.1.0")

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

The `import app.models  # noqa` line is the only addition. It's load-bearing — without it, tests using subsystem models get `Table not found` errors because their classes never registered.

## Failure modes to watch for

1. **Forgetting the `import app.models` in main.py.** Tests would silently miss tables for any subsystem that hasn't already been imported by something else. Catches: a model class exists in code but `Base.metadata.create_all` doesn't create its table. Symptom: `sqlalchemy.exc.OperationalError: no such table: <name>` in tests for that subsystem.

2. **Forward-declared relationships without the target class.** If sprint 001's `Volunteer.registrations` references `"Registration"` and sprint 002 hasn't defined `Registration` yet, SQLAlchemy raises `InvalidRequestError` at first use. Mitigation: the cross-sprint Type Ownership Map declares which sprints introduce which classes — sprint 002 spec must say "creates `Registration` model" before any test that touches `Volunteer.registrations` runs.

3. **Subsystem boundaries leaking.** If sprint 002's tests need to touch `Volunteer` directly (not via relationship), they should `from app.models.auth import Volunteer` — explicit import. Don't add re-exports to `app/models/__init__.py` beyond the auto-discovery itself; that introduces an additional source of truth and confuses what's owned where.

4. **Test fixture name collisions.** If `tests/fixtures/auth.py` defines `test_user` and `tests/fixtures/operations.py` also defines `test_user`, the auto-discovery's `globals()[name] = getattr(module, name)` clobbers based on import order. Mitigation: contract.md's Test Infrastructure section declares the fixture name space and which sprint owns which fixture.

5. **Per-sprint pyproject.toml additions racing.** Sprint N adds `twilio>=8.0` to dependencies; sprint N+1 doesn't see it because the runner's git workflow may have isolated sprints. Mitigation: the runner re-runs `uv sync --all-extras` before each sprint, so pyproject changes propagate. Verified working in prior NIFB runs.

## When this pattern is wrong

- **Tightly-coupled state across subsystems** — if half the project's logic lives in cross-cutting state machines (e.g., a workflow engine touching every entity), splitting by subsystem creates artificial seams. Fall back to all-front-loaded.
- **Languages/frameworks without auto-discovery support** — Go's `init()` pattern works analogously, TypeScript/Node typically uses explicit imports (no auto-discovery), Rust has no equivalent for module scanning. For non-Python projects, decide per-language whether auto-discovery is feasible. If not, use explicit-imports + the all-front-loaded pattern.
- **Project size below threshold** — if there are 5 entities total, splitting into subsystems is over-engineering. Use all-front-loaded.

## Validation

When the architect picks subsystem-front-loaded, the resulting specs should satisfy:

- [ ] Sprint 001 ≤ 700 lines spec (foundation + auth subsystem only)
- [ ] Sprints 002+ each ≤ 500 lines spec
- [ ] Every sprint's `## Modified files: (none — auto-discovery handles it)` (after sprint 001)
- [ ] `app/models/__init__.py` does pkgutil auto-import
- [ ] `app/main.py` imports `app.models` to trigger model registration
- [ ] Cross-subsystem relationships use forward-string references in the owner module
- [ ] contract.md's Sprint File-Ownership Map lists per-subsystem module names
- [ ] contract.md's Type/Symbol Ownership Map declares which subsystem owns which class
- [ ] No FROZEN file is modified after its initial creation in any sprint

## Architectural decision pinning in contract.md

The architect MUST declare the chosen pattern in `contract.md`'s opening section:

```markdown
## Architectural Pattern

This project uses **subsystem-front-loaded** architecture: each sprint
front-loads its own subsystem's models, schemas, services, and tests as
NEW files. Auto-discovery for both routers (`pkgutil.iter_modules` in
main.py) AND models (`pkgutil.iter_modules` in app/models/__init__.py)
means later sprints don't modify any earlier-sprint file.

Reasoning: 18 ORM entities + 16 sprints exceeds the size at which a
single front-loaded foundation sprint stays manageable. Subsystems map
cleanly to the sprint plan.

See `local_code_gen/principles/SUBSYSTEM-FRONT-LOADED.md` in the pipelines repo for the full pattern.
```

This pin makes downstream review (and any failure forensics) easier because the architecture choice is explicit and rationale-backed, not implicit in spec sizes.
