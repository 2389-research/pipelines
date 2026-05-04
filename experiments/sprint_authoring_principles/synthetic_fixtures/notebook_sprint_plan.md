# Notebook API — Sprint Plan

## Summary

Three sprints. Sprint 001 front-loads all foundation: every ORM model, every Pydantic schema, AppError, JWT auth, the auto-discovery `main.py`, the conftest, and the auth router. Sprints 002 and 003 are purely additive — they drop new files in `app/routers/` and `tests/` and the auto-discovery picks them up. After Sprint 001, the foundation files (`main.py`, `models.py`, `schemas.py`, `exceptions.py`, `database.py`, `config.py`, `conftest.py`) are FROZEN.

## FR Coverage Matrix

| Sprint | FR1 (auth) | FR2 (notes) | FR3 (tags model) | FR4 (filter) | FR5 (CRUD) | FR6 (health) |
| ------ | ---------- | ----------- | ---------------- | ------------ | ---------- | ------------ |
| 001    | full       | model only  | model only       | —            | —          | full         |
| 002    | —          | routes      | —                | —            | notes CRUD | —            |
| 003    | —          | —           | routes           | full         | tag CRUD   | —            |

## Sprint 001 — Core Foundation & Auth

**Scope.** Project scaffolding (pyproject.toml, hatchling build config, src layout). All three SQLAlchemy ORM models (User, Note, Tag, note_tags). All Pydantic v2 schemas (UserCreate, UserRead, TokenResponse, NoteCreate, NoteUpdate, NoteRead, TagCreate, TagRead). The `AppError` exception with flat-shape JSON handler. JWT issue/verify helpers. `/auth/signup` and `/auth/login` routes. `/health` endpoint. Auto-discovery `main.py` with pkgutil scanning of `app/routers/`. Database session dependency. Full `conftest.py` with in-memory SQLite + StaticPool, dependency overrides for `get_db` and `get_current_user`, an `auth_headers` fixture that mints a JWT for a seeded test user.

**FRs covered.** FR1 (full), FR2 (model only), FR3 (model only — User, Note, Tag, note_tags table), FR6 (full).

**Files (new).** All foundation files. Owns:

- `backend/pyproject.toml`
- `backend/app/__init__.py` (empty marker)
- `backend/app/main.py` (auto-discovery factory; FROZEN after this sprint)
- `backend/app/config.py` (Settings via pydantic-settings; FROZEN)
- `backend/app/database.py` (engine, session, get_db dep; FROZEN)
- `backend/app/exceptions.py` (AppError + handler; FROZEN)
- `backend/app/models.py` (User, Note, Tag, note_tags; FROZEN)
- `backend/app/schemas.py` (all Pydantic v2 schemas; FROZEN)
- `backend/app/auth.py` (password hashing + JWT issue/verify + `get_current_user` dep)
- `backend/app/dependencies.py` (re-exports of common deps for routers)
- `backend/app/routers/__init__.py` (empty marker)
- `backend/app/routers/auth.py` (signup + login)
- `backend/app/routers/health.py` (GET /health)
- `backend/scripts/init_db.py` (async runner that creates schema)
- `backend/tests/__init__.py` (empty marker)
- `backend/tests/conftest.py` (FROZEN — engine, session, client, auth_headers fixtures)
- `backend/tests/test_health.py`
- `backend/tests/test_auth.py`
- `backend/tests/test_models.py`
- `backend/tests/test_config.py`

**Files (modified).** None (this is the foundation sprint).

**Validation.** `cd backend && uv sync --all-extras && uv run pytest -v`. Tests cover: /health → 200, signup → 201 (email + password), signup duplicate → 409 with `error_code=USER_EXISTS`, login → 200 returns access_token, login bad credentials → 401, model field-set assertions.

## Sprint 002 — Notes CRUD (additive)

**Scope.** Notes router with full CRUD. POST /notes (with optional `tag_ids` list), GET /notes (own only), GET /notes/{note_id}, PATCH /notes/{note_id}, DELETE /notes/{note_id}. All auth-required. Cross-user isolation strictly enforced (404 if note exists but belongs to another user — never leak existence).

**FRs covered.** FR2 (routes), FR5 (notes CRUD).

**Files (new).**

- `backend/app/routers/notes.py` (drops into auto-discovery)
- `backend/tests/test_notes.py`

**Files (modified).** (none — `main.py` auto-discovers the new router; no changes to schemas, models, or conftest)

**Validation.** `cd backend && uv run pytest tests/test_notes.py -v`. Tests cover: create note → 201, list returns only own notes, GET other user's note → 404, PATCH mine → 200 with updated_at advancing, DELETE → 204 then GET → 404.

## Sprint 003 — Tags + tag-filter (additive)

**Scope.** Tags router with CRUD. POST /tags, GET /tags (own only), DELETE /tags/{tag_id} (cascade-unlinks from notes via note_tags FK). PLUS the additive tag-filter endpoint GET /notes/by-tag/{tag_id} that lives in a NEW router file `app/routers/notes_by_tag.py` so we never touch `notes.py`. Returns notes (own + tagged with that tag); 404 if the tag doesn't belong to the user.

**FRs covered.** FR3 (routes), FR4 (tag-filter), FR5 (tag CRUD).

**Files (new).**

- `backend/app/routers/tags.py`
- `backend/app/routers/notes_by_tag.py` (the additive filter endpoint — separate file so we don't modify notes.py)
- `backend/tests/test_tags.py`
- `backend/tests/test_notes_by_tag.py`

**Files (modified).** (none — same auto-discovery story; the deliberate split keeps notes.py FROZEN)

**Validation.** `cd backend && uv run pytest tests/test_tags.py tests/test_notes_by_tag.py -v`. Tests cover: tag CRUD; cross-user tag isolation (404 on other user's tag); /notes/by-tag/{tag_id} returns only notes belonging to caller AND tagged with that tag; deleting a tag unlinks it from notes (notes themselves persist).

## Cross-sprint invariants (load-bearing)

- The error-handler shape `{"detail": str, "error_code": str}` is set by Sprint 001's `AppError` and tested in EVERY sprint via the `client` fixture. All sprints assert `body["error_code"]` (flat path).
- All path/query parameters are typed `uuid.UUID` (never `str`).
- Collection routes use empty-string path `""` (never `"/"`).
- Static-path routes (e.g., `/notes/by-tag/{tag_id}`) live in a separate router so they don't conflict with `/notes/{note_id}` ordering. Even within `notes_by_tag.py`, the static segment `by-tag` precedes the dynamic `{tag_id}` parameter — no risk of route-order ambiguity since they're in different files.
- All ORM relationships use `lazy="selectin"` on the collection side; bidirectional relationships use `back_populates` on both sides.
- conftest's engine fixture uses `poolclass=StaticPool` so all connections share the same in-memory DB.
