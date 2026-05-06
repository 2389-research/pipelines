# Spec Analysis: Notebook API

## Project Summary

- **Name:** Notebook API
- **Purpose:** A small async Python web service for personal notes. Each user has notes; notes can be tagged.
- **Audience:** Single-deployment SaaS-style; one Postgres database.
- **Tech stack:** FastAPI + SQLAlchemy 2.x async + Pydantic v2 + pytest + JWT auth.
- **Database:** SQLite (test, in-memory) / Postgres (prod).
- **Package manager:** `uv` with `pyproject.toml` (hatchling backend).

## Functional Requirements

| ID  | Description                                                                                      |
| --- | ------------------------------------------------------------------------------------------------ |
| FR1 | Users can register with email + password and log in to receive a JWT access token.               |
| FR2 | Each user owns notes. A note has a title (≤200 chars) and a body (markdown text).                |
| FR3 | Notes can be tagged. Each tag is per-user (scoped to its owner). A note has 0+ tags.             |
| FR4 | Users can list their notes, optionally filtered by a single tag (returns notes that own the tag).|
| FR5 | Full CRUD on notes; create/list/delete on tags (no rename). All data routes require a valid JWT. |
| FR6 | Public `/health` endpoint that returns `{"status": "ok"}`.                                       |

## Components

| ID | Component | Responsibilities                                                                  |
| -- | --------- | --------------------------------------------------------------------------------- |
| C1 | Auth      | Signup, login, JWT issue/verify, password hashing.                                |
| C2 | User      | Account record (email + password hash). Owner of notes and tags.                  |
| C3 | Note      | CRUD; list (own only); tag-filtered list.                                         |
| C4 | Tag       | Create/list/delete per-user. Tag a note (many-to-many via `note_tags`).           |

## Entities (high level — exact field sets pinned in contract.md)

- **User** — `id (UUID, PK)`, `email (str, unique)`, `password_hash (str)`, `created_at (datetime)`.
- **Note** — `id (UUID, PK)`, `owner_id (UUID, FK→users.id)`, `title (str ≤200)`, `body (str)`, `created_at (datetime)`, `updated_at (datetime)`.
- **Tag** — `id (UUID, PK)`, `owner_id (UUID, FK→users.id)`, `name (str ≤50)`. Unique per `(owner_id, name)`.
- **note_tags** — link table `(note_id UUID, tag_id UUID)`, both PK; both FKs cascade-delete.

## Routes (high level)

| Component | Method | Path                          | Auth | Notes                                 |
| --------- | ------ | ----------------------------- | ---- | ------------------------------------- |
| Auth      | POST   | /auth/signup                  | no   | Body: email + password.                |
| Auth      | POST   | /auth/login                   | no   | Returns `{access_token, token_type}`.  |
| Health    | GET    | /health                       | no   | `{status: "ok"}`.                      |
| Notes     | POST   | /notes                        | yes  | Create note (optional tag_ids).        |
| Notes     | GET    | /notes                        | yes  | List notes (own only).                 |
| Notes     | GET    | /notes/by-tag/{tag_id}        | yes  | List notes filtered by tag.            |
| Notes     | GET    | /notes/{note_id}              | yes  | Get note (own only).                   |
| Notes     | PATCH  | /notes/{note_id}              | yes  | Update title/body/tag_ids.             |
| Notes     | DELETE | /notes/{note_id}              | yes  | Delete note.                           |
| Tags      | POST   | /tags                         | yes  | Create tag.                            |
| Tags      | GET    | /tags                         | yes  | List own tags.                         |
| Tags      | DELETE | /tags/{tag_id}                | yes  | Delete tag (also unassigns from notes).|

## Architectural Notes

- **Front-loaded foundation** applies cleanly. Three entities are known up front; auth shape is stable. Sprint 001 declares all ORM models, all Pydantic schemas, the `AppError` exception type, the JWT handler, the auth router, the auto-discovery `main.py`, and the full conftest. Sprints 002+ are purely additive routers.
- **Auto-discovery main.py** uses `pkgutil.iter_modules(...)` to scan `app/routers/` and register any module exposing a `router` attribute. New routers drop in without modifying `main.py`.
- **Tag-filter route is additive-by-design.** Putting tag filtering on a separate path `/notes/by-tag/{tag_id}` (instead of a query param on `/notes`) means Sprint 003 doesn't need to modify `app/routers/notes.py` — it can ship its own additive endpoint. This is the deliberate design trade for keeping later sprints frozen against earlier files.
- **Async loading strategy:** SQLAlchemy 2.x async with `lazy="selectin"` on collection-side relationships. Bidirectional relationships use `back_populates` on both sides.
- **Test fixtures:** in-memory SQLite with `StaticPool` (otherwise each connection gets a fresh DB).
- **Error handling:** custom `AppError` exception with a flat JSON shape `{"detail": str, "error_code": str}`. Tests assert `body["error_code"]` (not nested).
