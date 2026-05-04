# 14 Defect Classes — Architect's Pre-Shipping Checklist

These are the categories of "qwen makes a reasonable inference that breaks at runtime" we encountered during the v3→v7 NIFB iteration on Apr 30, 2026. Each one has a runtime symptom and a spec rule that closes it. **The architect MUST close all 14 before shipping a sprint spec.**

The meta-pattern: **spec leaves a gap → qwen fills it with a "reasonable-looking" choice → fails at runtime.** A 30-token spec rule prevents an entire class. The cost of catching these at spec time vs runtime is dramatically asymmetric.

## The 14 classes

### 1. Build-system block missing backend-specific config

**Symptom:** `uv sync` crashes during editable install before any test runs. `hatchling.build.build_editable` fails to detect a package directory.

**Why:** Hatchling's auto-detection looks for a directory matching the project name (after normalizing hyphens). A project named `nifb-backend` with package directory `app` doesn't match — auto-detection fails.

**Spec rule:** When using hatchling and project name ≠ package dir name, include `[tool.hatch.build.targets.wheel] packages = ["<dir>"]` verbatim. Same principle for `setuptools` (`find_packages` config), `poetry` (`packages` array), etc.

### 2. Bare module name in imports list

**Symptom:** `sqlalchemy.orm.exc.MappedAnnotationError: object provided ... is not a Python type, it's the object <module 'datetime'>` at SQLAlchemy mapping time.

**Why:** When the spec lists imports as `enum`, `uuid`, `datetime`, qwen interprets these as `import enum`, `import uuid`, `import datetime`. For `datetime`, that imports the MODULE; subsequent `Mapped[datetime]` annotations fail because the column type needs the CLASS.

**Spec rule:** Imports are full Python statements, never bare module names. For class-vs-module collisions (`datetime`, `date`, `time`, `decimal.Decimal`), use `from X import Y` form explicitly.

### 3. Tests reference Pydantic Settings class attributes

**Symptom:** `AttributeError: OTP_BYPASS_CODE` from `pydantic._internal._model_construction` when the test runs.

**Why:** Pydantic v2's `BaseSettings` stores fields on instances, not as class attributes. `Settings.OTP_BYPASS_CODE` raises AttributeError. `Settings().OTP_BYPASS_CODE` works.

**Spec rule:** Tests use literal values for config-derived constants (`"000000"` directly). If a test must read live config, instantiate `Settings()` and read the instance attribute. **Class-attr access (`Settings.X`) on BaseSettings is forbidden.**

### 4. Test builds its own client/engine/session inline

**Symptom:** `TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'` (or other API drift), or per-test isolation broken.

**Why:** qwen, when generating a test file, infers it should set up the test infrastructure itself rather than depending on conftest.

**Spec rule:** Tests take fixtures (`client`, `db_session`, `volunteer_factory`) as **function parameters**. `conftest.py` is the single point of test setup; per-test self-sufficiency is forbidden.

### 5. Async ORM relationships missing `lazy="selectin"`

**Symptom:** `sqlalchemy.exc.MissingGreenlet: greenlet_spawn has not been called; can't call await_only() here.` on `obj.collection_field` access.

**Why:** SQLAlchemy 2.x async sessions don't permit lazy loads on attribute access. Without an explicit loading strategy, accessing `shift.registrations` after the session has closed (or in a context that's not in a greenlet) raises `MissingGreenlet`.

**Spec rule:** Every collection-side `relationship(...)` MUST include `lazy="selectin"`. Singular (many-to-one) sides do not need it. List the affected relationships explicitly so qwen can't omit any.

### 6. Fixture-dependent helper defined at module level instead of as a closure

**Symptom:** `sqlalchemy.exc.ArgumentError: AsyncEngine expected, got <pytest_fixture(<function async_engine>)>` (helper bound to the fixture decorator object instead of the resolved value).

**Why:** When the spec describes a helper like `override_get_db` that references a fixture-resolved value (e.g., `async_engine`), qwen has a tendency to define it at module level. At module level, `async_engine` is the pytest fixture function reference (a `FixtureFunctionDefinition`), not the resolved engine instance.

**Spec rule:** The helper must be a **nested closure inside the consuming fixture**:

```python
@pytest_asyncio.fixture
async def client(async_engine, db_session):
    factory = async_sessionmaker(async_engine, expire_on_commit=False)
    async def override_get_db():
        async with factory() as s:
            yield s
    ...
```

Spec must explicitly say "defined INSIDE the fixture body, NOT at module level."

### 7. Path/query parameter typed as `str` instead of `uuid.UUID`

**Symptom:** `AttributeError: 'str' object has no attribute 'hex'` from `sqlalchemy/sql/sqltypes.py` when handling a UUID column. Routes still receive the request, but SQLAlchemy's UUID column bind processor expects UUID instances.

**Why:** When the API contract is described in a path-pattern table (`/locations/{location_id}`) without explicit Python signatures, qwen defaults parameters to `str`. FastAPI doesn't auto-parse the path to UUID without the annotation.

**Spec rule:** API contract MUST specify each path/query param's Python type explicitly. Don't rely on the path pattern alone — qwen needs the annotation. Examples:
- `location_id` (path) — `uuid.UUID`
- `on_date` (query) — `date | None = None`
- `location_id` (query) — `uuid.UUID | None = None`

### 8. qwen invents schema/model fields based on "reasonable" pattern-matching

**Symptom:** `AttributeError: 'Shift' object has no attribute 'station_id'` (or similar phantom-attribute access).

**Why:** qwen sees "Shift" + "Station" both in the data contract and infers a relationship that doesn't actually exist. The relationship lives on `Assignment`, not directly on `Shift`. qwen "helpfully" passes `station_id=shift.station_id` when constructing a `ShiftRead` schema.

**Spec rule:** Algorithm steps that construct a Read schema explicitly MUST list the **exact** field set: "construct ShiftRead with EXACTLY these fields and no others: id, location_id, title, ... — do NOT pass any other field." Plus a Rule: "Pydantic Read schemas have EXACTLY the fields declared in sprint 001's data contract; do not invent fields."

### 9. In-memory SQLite test engine missing `StaticPool` + `connect_args`

**Symptom:** Test fails because data committed via the API isn't visible to a follow-up `db_session.execute(select(...))` — looks like the API didn't commit, but it actually did, just into a different in-memory DB.

**Why:** With `sqlite+aiosqlite:///:memory:` and the default `NullPool`, every connection gets its OWN in-memory database. The API's override session and the test's `db_session` end up on separate DBs.

**Spec rule:** Test conftest's async engine MUST be:

```python
create_async_engine(
    "sqlite+aiosqlite:///:memory:",
    echo=False,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
```

Plus `from sqlalchemy.pool import StaticPool`. Spec must declare these args verbatim — qwen omits them by default since they're not "obvious" engine config.

### 10. Trailing-slash on collection routes

**Symptom:** `assert 307 == 200` on collection-route tests. AsyncClient gets a redirect and doesn't follow it by default.

**Why:** qwen writes `@router.post("/", ...)` (with trailing slash) under prefix `/locations` → route URL is `/locations/`. Tests calling `/locations` (no slash) get 307.

**Spec rule:** Collection-level routes use empty-string path `""` (not `"/"`). Example: `@router.post("", ...)` correct; `@router.post("/", ...)` wrong.

### 11. Route declaration order with parameterized paths

**Symptom:** `422 Unprocessable Entity` on a static-path route that should match cleanly. The underlying error is "value is not a valid UUID" for a path segment that looks like a verb (`browse`, `me`, etc.).

**Why:** FastAPI matches routes in declaration order. If `@router.get("/{shift_id}")` is declared before `@router.get("/browse")`, every request to `/shifts/browse` matches the parameterized route with `shift_id="browse"` and fails UUID parsing.

**Spec rule:** Within a router, declare static-path routes BEFORE parameterized routes that share their prefix. List the order explicitly in the API contract.

### 11-bis (meta-rule): Structural sections must match structural rules

A Rule that says "declare static routes before parameterized" is ineffective if the API contract table itself lists routes in the wrong order. **qwen follows the structure of the spec, not the prose rules — when a Rule and a structural section conflict, qwen uses the structure.**

When adding a structural rule (route order, field order, declaration order), reorder ALL the structured sections (API tables, algorithm subsections, signature blocks) to match. Rules in prose are not enough.

### 12. Tests use raw string UUIDs from JSON responses in ORM queries

**Symptom:** `AttributeError: 'str' object has no attribute 'hex'` originating from `sqlalchemy/sql/sqltypes.py` during a test's `db_session.execute(select(...).where(...))` call.

**Why:** `response.json()["id"]` is a string. Passing it directly to a SQLAlchemy filter on a UUID column makes SQLAlchemy's bind processor call `.hex` on the string.

**Spec rule:** Tests parse string ids back to UUID with `uuid.UUID(...)` before using in ORM queries:

```python
reg_id = uuid.UUID(response.json()["id"])
result = await db_session.execute(select(Registration).where(Registration.id == reg_id))
```

### 13. Tests pass `date`/`time`/`datetime`/`uuid.UUID` objects in `json=` body

**Symptom:** `TypeError: Object of type date is not JSON serializable` (or `time`, `datetime`, `UUID`) at httpx's request build step.

**Why:** httpx's `json=` argument uses Python's stdlib `json.dumps`, which can't serialize these types.

**Spec rule:** Tests serialize non-primitive values with `.isoformat()` (date/time/datetime) or `str(...)` (UUID) before passing to `json=`.

```python
json={
    "date": date.today().isoformat(),
    "start_time": time(9, 0).isoformat(),
    "location_id": str(test_location.id),
    ...
}
```

### 14. Test assertions don't match the API's actual error-response shape

**Symptom:** `TypeError: string indices must be integers, not 'str'` on a `body["detail"][...]` lookup in tests asserting error responses.

**Why:** Custom exception handlers (e.g., `AppError` returning `{"detail": str, "error_code": str}` flat) produce a different JSON shape than FastAPI's default HTTPException handler (which nests as `{"detail": {...}}`). When the architect writes test asserts using the wrong path, qwen transcribes faithfully and tests fail.

**Spec rule:** The architect must (a) state the exception handler's exact JSON shape in Tricky Semantics, AND (b) write all test assertions for error responses using the matching path.

For a flat handler (`{"detail": str, "error_code": str}`), tests assert `body["error_code"]` directly. For a nested handler, tests assert `body["detail"]["error_code"]`. **The test contract must match the handler — mixing forms = silent failure at test time.**

## Summary checklist (architect runs this before shipping)

- [ ] Class 1: Every config file (`pyproject.toml`, etc.) has all backend-specific blocks (hatch wheel.packages, etc.).
- [ ] Class 2: Every Imports list (in `## New files` bullets) is full Python statements, never bare module names. Audit for class-vs-module collisions.
- [ ] Class 3: Tests use literal string values for config-derived constants. No `Settings.X` references in test code.
- [ ] Class 4: Test contract says "tests take fixtures as parameters." No test file constructs its own `AsyncClient`, engine, or session.
- [ ] Class 5: Every collection-side `relationship(...)` has `lazy="selectin"`. Pairs listed explicitly.
- [ ] Class 6: Fixture-dependent helpers (`override_get_db` etc.) declared as closures inside the fixture body.
- [ ] Class 7: Path/query parameter types use real Python types (`uuid.UUID`, `date`), not `str`.
- [ ] Class 8: Read schemas have EXACTLY the fields declared. Algorithm sections list field sets explicitly when constructing schemas.
- [ ] Class 9: `async_engine` fixture uses `StaticPool` + `connect_args={"check_same_thread": False}`.
- [ ] Class 10: Collection routes use empty-string path `""` not `"/"`.
- [ ] Class 11: Static routes declared before parameterized routes with overlapping prefixes — IN BOTH the rule AND the API contract table.
- [ ] Class 12: Tests parse string ids with `uuid.UUID(...)` before ORM queries.
- [ ] Class 13: Tests serialize date/time/datetime via `.isoformat()` and UUID via `str(...)` for JSON bodies.
- [ ] Class 14: Test error-response assertions match the exception handler's JSON shape (flat vs nested).
- [ ] Meta (11-bis): All structural sections (tables, signatures, algorithm subsections) are internally consistent with the Rules section.
