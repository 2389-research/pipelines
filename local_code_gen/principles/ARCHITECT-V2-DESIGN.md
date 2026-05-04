# Architect_v2 Design — All-front-loaded foundation + auto-discovery + FROZEN files

One of two sibling architecture patterns the architect can choose between:

| Pattern | When to use | Where documented |
|---|---|---|
| **All-front-loaded** (this doc) | Small projects: ≤7 entities, ≤4 sprints, foundation sprint fits in ~600 lines spec | This doc |
| **Subsystem-front-loaded** | Large projects: ≥8 entities, ≥5 sprints, OR sprint plan decomposes naturally by subsystem | [`SUBSYSTEM-FRONT-LOADED.md`](SUBSYSTEM-FRONT-LOADED.md) |

The architect picks per-project from the spec_analysis + sprint_plan inputs and **declares the choice in `contract.md`'s opening section** with one-paragraph reasoning. See "Architectural decision pinning" at the bottom of [`SUBSYSTEM-FRONT-LOADED.md`](SUBSYSTEM-FRONT-LOADED.md) for the format.

This doc covers all-front-loaded — the simpler default. Validated through pipeline run on Apr 30, 2026: sprint 002 added 4 new routers + 4 new test files with **zero modifications to any sprint 001 file**.

The all-front-loaded pattern works well up to ~7 ORM entities. Beyond that, a single foundation sprint exceeds the writer model's output budget (the May 1 NIFB run hit this — Sonnet truncated mid-Rules section on a 1068-line SPRINT-001 spec). Use subsystem-front-loaded for those.

## The problem this solves

Earlier "incremental APPEND" architecture (V1) had each sprint patch sprint 001's `models.py`, `schemas.py`, `main.py` to add new entities/schemas/routes. The local model would routinely:

- Wipe parts of `models.py` while patching (writing only the new content, dropping the existing entities)
- Get the merge wrong on `schemas.py` and lose Sprint N-1's schemas
- Add `app.include_router(...)` calls in `main.py` while accidentally renaming or deduplicating prior includes

These cascade failures couldn't be fixed by the patch loop — they corrupted the foundation that sprint N+1 depended on. The validation guards we added (line-count floor, symbol preservation) caught some of it, but not all.

V1 multi-sprint runs hit at-most 1-2 sprints before falling apart.

## The fix: front-load + auto-discover + freeze

**Front-load.** Sprint 001 declares the entire surface area for the project: every ORM model, every Pydantic schema, every error code constant, every test fixture, plus the FastAPI app factory. After sprint 001, those files are FROZEN.

**Auto-discover.** `main.py` doesn't import routers by name. It uses `pkgutil.iter_modules(routers_pkg.__path__)` to scan `app/routers/` and call `app.include_router(module.router)` for any module that exposes a `router: APIRouter`. Sprints 002+ drop a new file in `app/routers/<feature>.py` and it auto-registers — never modify `main.py`.

**Freeze.** The Rules section of sprint 001 lists the FROZEN files. Sprint N's spec inherits this. The architect/writer NEVER produces a `## Modified files` entry for a frozen file; the local generator NEVER edits one.

## What sprint 001 must declare

Mandatory (no later sprint may add to these — they're FROZEN):

- **`backend/app/models.py`** — every ORM model + every enum across ALL sprints. Sprint 001 implements the auth flow's models (`Volunteer`, `OTP`); the rest are declared but not used until later sprints' routers wire them up.
- **`backend/app/schemas.py`** — every Pydantic request/response schema across ALL sprints, by the same logic.
- **`backend/app/exceptions.py`** — `AppError` exception class + every error code constant string (`ACCOUNT_EXISTS`, `NOT_FOUND`, `SHIFT_FULL`, etc.).
- **`backend/app/database.py`** — `Base(DeclarativeBase)`, lazy `get_engine()` / `get_session_factory()`, async `get_db()` dependency.
- **`backend/app/config.py`** — `Settings(BaseSettings)` + cached `get_settings()` factory.
- **`backend/app/main.py`** — FastAPI app factory with `pkgutil` router auto-discovery + the `AppError` global exception handler. Module-level `app = create_app()` so tests can `from app.main import app`.
- **`backend/tests/conftest.py`** — every fixture across all sprints (`async_engine` with StaticPool, `db_session`, `client`, `test_volunteer`, `auth_headers`, `test_location`, `test_station`, `test_shift`, etc.).

The ONE foundation file later sprints may modify: `pyproject.toml` — to append new deps under `[project.dependencies]` when a sprint introduces a new library (e.g., Sprint 005 adds Twilio). They do not touch any other section.

## The auto-discovery main.py (verbatim — load-bearing)

```python
import importlib
import pkgutil

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

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

    # Auto-discover and include every router file in app.routers/
    for _, modname, _ in pkgutil.iter_modules(routers_pkg.__path__):
        module = importlib.import_module(f"app.routers.{modname}")
        if hasattr(module, "router"):
            app.include_router(module.router)

    return app


app = create_app()
```

Notes:
- The exception handler returns the **flat** form `{"detail": str, "error_code": str}` — NOT `{"detail": {...}}` nested. Tests must assert `body["error_code"]` directly. (See [`DEFECT-CLASSES.md`](DEFECT-CLASSES.md) #14.)
- The empty package marker `app/routers/__init__.py` is load-bearing: pkgutil's `iter_modules(routers_pkg.__path__)` requires the package to exist.
- Routers MUST expose their `APIRouter` instance as the module-level name `router`. Without this, the `hasattr(module, "router")` check skips them silently.

## What sprint 002+ looks like

Pure-additive sprints contain only:
- `## New files` — list of new files to create (typically 1 router + 1 test file per feature)
- `## Modified files: (none — main.py auto-discovers; models/schemas frozen)`
- The router in `app/routers/<feature>.py` declares `router = APIRouter(prefix="/<resource>", tags=["<resource>"])` and the handlers
- The test file in `tests/test_<feature>.py` uses fixtures from conftest

Cross-sprint coupling is minimized to:
- Importing pre-existing models/schemas/error codes
- Using pre-existing test fixtures

## When this design doesn't apply

The pattern assumes:
- A relatively known data model (so front-loading entities at sprint 001 is feasible)
- A small-to-medium project size (≤7 ORM entities) — beyond that the foundation sprint becomes too big for a single LLM author pass and you should use [`SUBSYSTEM-FRONT-LOADED.md`](SUBSYSTEM-FRONT-LOADED.md) instead
- A web-framework backend with router-style architecture
- Single-package layout (one `app/` directory)

For larger projects where the data model decomposes by subsystem (auth + operations + groups + messaging, etc.) and the sprint plan already reflects that decomposition, switch to [subsystem-front-loaded](SUBSYSTEM-FRONT-LOADED.md). For projects with truly unknown data models that emerge sprint-by-sprint, neither pattern is a perfect fit — and a different incremental architecture is needed.

## Architect-side checklist for the foundation sprint (001)

Before shipping sprint 001, the architect should be able to answer "yes" to ALL of these:

- [ ] All models that any sprint will use are in `app/models.py`. Each has full field signatures, including relationships with `back_populates` on both sides AND `lazy="selectin"` on every collection-side relationship.
- [ ] All Pydantic schemas that any sprint will use are in `app/schemas.py`. Read schemas use `model_config = ConfigDict(from_attributes=True)`.
- [ ] `app/main.py` uses pkgutil router discovery — no hardcoded `app.include_router(...)` calls.
- [ ] `app/exceptions.py` declares `AppError(HTTPException)` + every error code constant the project will use.
- [ ] `app/database.py` uses lazy engine init (`get_engine()`/`get_session_factory()` with module-level globals — NOT `create_async_engine` at import time).
- [ ] `tests/conftest.py` async_engine uses `StaticPool` + `connect_args={"check_same_thread": False}` for in-memory SQLite cross-session visibility.
- [ ] `tests/conftest.py` `client` fixture defines `override_get_db` as a CLOSURE inside the fixture body (not at module level).
- [ ] FROZEN files listed explicitly in the spec's Rules section.
- [ ] `pyproject.toml` includes `[tool.hatch.build.targets.wheel] packages = ["app"]` (when project name ≠ package dir name).
