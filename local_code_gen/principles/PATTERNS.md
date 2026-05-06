# Patterns — consolidated by where each lives at runtime

The 14 [defect classes](DEFECT-CLASSES.md) are 14 *instances* but ~7 *patterns*. This doc consolidates them, grouped by which model needs to know about each one.

The two models in the pipeline:
- **Opus** runs the `write_sprint_docs` agent in `local_code_gen/spec_to_sprints.dip` (and the architect-only sibling `local_code_gen/architect_only.dip`). It writes `.ai/contract.md` ONCE per project and dispatches per-sprint enrichment via the `dispatch_sprints` tool.
- **Sonnet** runs inside the `write_enriched_sprint` tool (in the tracker repo at `tracker/agent/tools/write_enriched_sprint.go`). It expands one `SPRINT-NNN.md` per call, reading `.ai/contract.md` for cross-sprint pins.

A pattern lives at the Opus layer if it's a project-wide convention pinned ONCE in `contract.md`. A pattern lives at the Sonnet layer if it's applied per-sprint, per-file, or per-test.

---

## Opus patterns (cross-sprint, pinned in `.ai/contract.md`)

### O-1. Architectural pattern: front-loaded foundation + auto-discovery + FROZEN files

Sprint 001 declares the entire surface area: every ORM model, every Pydantic schema, every error code constant, every test fixture, plus a FastAPI app factory using `pkgutil.iter_modules` to auto-discover routers. After sprint 001, a fixed list of files is FROZEN; no later sprint may modify them. Sprints 002+ are purely additive — drop a new router file, it auto-registers.

**Why:** earlier "incremental APPEND" architecture had each sprint patching `models.py` / `schemas.py` / `main.py`. Cascading corruption ensued. Front-load + auto-discover + freeze eliminates the entire class of cross-sprint patch fragility.

**Defect-class instances closed:** N/A directly — this is the architectural choice that PREVENTS most cross-sprint failures from occurring at all.

**See:** [`ARCHITECT-V2-DESIGN.md`](ARCHITECT-V2-DESIGN.md) for the full design.

### O-2. Build/config blocks include backend-specific config

Every config-shaped file (`pyproject.toml`, `package.json`, `tsconfig.json`, `vite.config.ts`, etc.) must include backend-specific blocks that auto-detection won't infer. Don't ship the minimal `[build-system]` declaration alone.

**Examples that close defects we hit:**
- Hatchling: `[tool.hatch.build.targets.wheel] packages = ["app"]` when project name ≠ package dir.
- Setuptools: `find_packages(...)` config or src layout.
- Poetry: `packages` array.

**Defect-class instance:** #1 hatchling.

### O-3. Stack convention: error response shape is part of the cross-sprint contract

If the project uses a custom exception class (e.g., `AppError`) and its handler returns a JSON shape (e.g., flat `{"detail": str, "error_code": str}`), this shape MUST be pinned in contract.md. Every sprint's tests assert against it; if the shape isn't pinned, tests in different sprints will use different paths (`body["error_code"]` vs `body["detail"]["error_code"]`) and silently fail.

**Defect-class instance:** #14 — assertion path mismatch.

### O-4. Stack convention: async ORM loading strategy

If the project uses SQLAlchemy 2.x async, contract.md MUST pin the loading strategy on collection-side relationships (typically `lazy="selectin"`) and require `back_populates` on both sides of bidirectional pairs. Without this, every cross-sprint test that traverses a relationship hits `MissingGreenlet` at runtime and the architect can't tell from the symptom that it's a missing-loading-strategy issue.

**Defect-class instance:** #5 — `lazy="selectin"` missing.

### O-5. Stack convention: settings/config testing semantics

If the project uses Pydantic v2 `BaseSettings`, contract.md MUST pin: (a) the cached `get_settings()` factory pattern, (b) tests use literal values for config-derived constants, (c) class-attr access on `BaseSettings` (e.g., `Settings.X`) is forbidden (Pydantic stores fields on instances).

**Defect-class instance:** #3 — class-attr access.

### O-6. Stack convention: test infrastructure (DB pool + closure scope)

contract.md must pin test-infrastructure conventions that are easy to omit and hard to diagnose:

- In-memory SQLite tests need `connect_args={"check_same_thread": False}, poolclass=StaticPool` — without this, sessions land on different in-memory DBs and cross-session writes are invisible.
- Fixture-dependent helpers (e.g., `override_get_db`) MUST be closures inside the consuming fixture, NOT at module level.

**Defect-class instances:** #6, #9.

### O-7. Architect-discipline meta-rule: structural sections must embody structural rules

When contract.md (or a sprint spec) states a structural rule, the structural sections must reflect it. A Rule that says "static routes before parameterized" is ineffective if the API contract table itself lists routes in the wrong order. **The local generator follows the structure of the spec, not the prose rules.** When you state a rule, restructure tables, signatures, and algorithm subsections to embody it.

**Defect-class instance:** 11-bis (meta).

### O-8. Architect-discipline meta-rule: make a concrete choice and commit

Where the spec or sprint plan is ambiguous about implementation details, make a concrete choice and commit. Do not hedge with "you may use X or Y." The local generator has no preference — it needs one answer. If the architect leaves a choice open, the generator picks unpredictably.

This applies project-wide and across all sprints — Opus's job at contract.md time is to lock in choices like "the test bypass code is `"000000"`" (not "use `Settings.OTP_BYPASS_CODE`").

---

## Sonnet patterns (within-sprint, applied per-sprint by the writer)

### S-1. Speedrun section structure

Every SPRINT-NNN.md follows the speedrun format ([details](SPEEDRUN-SPEC-FORMAT.md)): Scope → Non-goals → Dependencies → Conventions → Tricky semantics → Data contract → API contract → Algorithm → Test contract → Verbatim files → New files → Modified files → Rules → DoD → Validation.

Use **signatures + algorithm prose + rules** for substantive code (routers, tests). Use **verbatim full text** only for tiny data-shaped files (`pyproject.toml`, `exceptions.py`, the auto-discovery `main.py`, etc.). Don't write impl-grade code into the spec for routers or tests — qwen produces idiomatic bodies given a tight contract.

### S-2. Per-file imports list as full Python statements

Every entry in `## New files` includes the EXACT imports list — full Python statements, never bare module names. For class-vs-module collisions (`datetime`, `date`, `time`, `decimal.Decimal`), use `from X import Y` form explicitly.

**Defect-class instance:** #2.

### S-3. Route discipline (within a router file)

- Path/query parameters annotated with real Python types (`uuid.UUID`, `date`, etc.) — never default to `str`.
- Collection routes use empty-string path `""`, NOT `"/"`.
- Static-path routes declared BEFORE parameterized routes that share their prefix.
- The route order in the API contract table matches the declaration order in the router file (see O-7 meta-rule).

**Defect-class instances:** #7, #10, #11.

### S-4. Schema discipline (when constructing schemas explicitly)

Algorithm steps that construct a Read schema (e.g., `ShiftRead(...)` with derived `registered_count`) MUST list the EXACT field set and instruct "do NOT pass any other field." Pydantic Read schemas have exactly the fields declared in contract.md's data contract; do not invent fields based on "what should be there."

**Defect-class instance:** #8.

### S-5. Test fixture discipline

Tests take fixtures (`client`, `db_session`, `auth_headers`, etc.) as **function parameters**. Test files contain only test functions; they NEVER construct `AsyncClient`, engines, or sessions inline. `conftest.py` is the single point of test setup (and it's pinned in contract.md per O-6).

**Defect-class instance:** #4.

### S-6. Test data serialization

Tests use literal values for config constants (per O-5). For HTTP request bodies and ORM filters:

- Date/time/datetime → `.isoformat()` before passing to `json=`.
- UUID → `str(...)` before passing to `json=` or interpolating into URL paths.
- String UUIDs from `response.json()["id"]` → parse via `uuid.UUID(...)` before using in ORM `select(...).where(...)` queries.

**Defect-class instances:** #12, #13.

### S-7. Test response-shape assertions match the handler's actual JSON

Tests assert error response paths matching contract.md's pinned handler shape. For a flat handler (`{"detail": str, "error_code": str}`), tests assert `body["error_code"]` directly — not `body["detail"]["error_code"]`. The Sonnet writer cross-references contract.md's handler shape pin (per O-3) when writing test asserts.

**Defect-class instance:** #14.

### S-8. Two-pass review

Sonnet produces SPRINT-NNN.md (Pass 1: convert into the speedrun format applying patterns S-1 through S-7). Then Sonnet runs Pass 2 — scrutinize the spec for ambiguity, conflict between sections, and gaps that qwen could fill in wrong. Patch and ship.

**See:** [`TWO-PASS-REVIEW.md`](TWO-PASS-REVIEW.md) for the full Pass 2 checklist.

---

## Why this isn't exhaustive

These patterns are an exemplar library, not a grammar. Frontier models work better given:
- A small set of well-described categories
- Concrete examples per category showing what right and wrong look like
- A meta-pattern statement (spec leaves a gap → local model fills it with reasonable-looking choice → fails at runtime)
- Reference materials (the [`exemplars/`](exemplars/)) to pattern-match against

…then asked to apply judgment, not check 14 boxes mechanically.

New stacks will surface new patterns. We expect this. The role of [`DEFECT-CLASSES.md`](DEFECT-CLASSES.md) is to record empirical evidence; the role of `PATTERNS.md` (this file) is to lift those into reusable categories. When a new defect surfaces:
1. Append to `DEFECT-CLASSES.md` (record).
2. Either fold into an existing pattern in this doc, or add a new pattern category if none fits.
3. Sync the relevant subset into the live prompts:
   - Opus → `local_code_gen/spec_to_sprints.dip` (and `architect_only.dip`)'s `write_sprint_docs` agent body.
   - Sonnet → `tracker/agent/tools/write_enriched_sprint.go`'s system prompt.
