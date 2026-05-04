# Structural fix: test plan

**Status: TEST PLAN (historical, May 1 2026).** How we validated the [structural fix](STRUCTURAL-FIX-PROPOSAL.md) (Opus designs, tracker tool dispatches) before shipping it. Each piece tested in isolation; integration tests use a small synthetic project so we can verify outputs by hand without paying NIFB-scale cost.

> **Note on paths in this document:** this plan was written before the May 4 reorganization that moved the dips into `local_code_gen/`. References to `architect_only_test.dip`, `experiments/sprint_authoring_principles/` etc. are accurate to the layout at writing time. Current paths: `local_code_gen/architect_only.dip`, `local_code_gen/principles/synthetic_fixtures/`. The test outcomes themselves are documented in [`STRUCTURAL-FIX-RESULTS.md`](STRUCTURAL-FIX-RESULTS.md).

## Why a synthetic test fixture

NIFB is too big to iterate on cheaply. Each end-to-end run is ~$3-5 and 30+ min. Hard to A/B prompt changes against. A 3-sprint synthetic project costs ~$1 and runs in ~3-5 min. Fast iteration loop while we're tuning the new architecture.

We'll use NIFB as the **acceptance test** once the synthetic project is green.

## Synthetic fixture: "Notebook API" (3 sprints)

A tiny async-Python web API for personal notes, with auth and tags. Chosen because it exercises every pattern category we care about (front-loaded foundation, auto-discovering routers, async ORM, JWT auth, multi-entity relationships, tag-based filtering) at small scale.

### Synthetic `.ai/spec_analysis.md` outline

```markdown
# Spec Analysis: Notebook API

## Project Summary
- Name: Notebook API
- Purpose: A simple personal-notes service with user accounts, notes, and tags.
- Tech stack: FastAPI + SQLAlchemy 2.x async + Pydantic v2 + pytest, SQLite (test) / Postgres (prod).

## Functional Requirements
| ID | Description |
|---|---|
| FR1 | User accounts with email/password registration and JWT-based login |
| FR2 | Each user owns notes; notes have a title, body (markdown), and timestamps |
| FR3 | Notes can be tagged; each note has 0+ tags, each tag is per-user |
| FR4 | List notes by user (own only) with optional filter by tag |
| FR5 | Create/read/update/delete notes; tag CRUD; auth required for all data routes |
| FR6 | /health endpoint (public) |

## Components
- C1: Auth (signup, login, JWT)
- C2: User account
- C3: Note (CRUD, list, filter)
- C4: Tag (CRUD)

## Architectural Notes
- Front-loaded foundation pattern applies (3 entities + auth, all in sprint 001).
- Sprints 002+ are purely additive routers via pkgutil auto-discovery.
```

(About 30 lines; 1 page. Realistic enough to drive contract design.)

### Synthetic `.ai/sprint_plan.md` outline

```markdown
# Notebook API Sprint Plan

## Summary
Three sprints. Sprint 001 front-loads everything. Sprints 002-003 are purely additive.

## Sprint 001 — Core Foundation & Auth
**Scope:** All 3 ORM models (User, Note, Tag) + all schemas + AppError + JWT auth + /auth/signup, /auth/login + /health + full conftest.
**FRs:** FR1, FR2 (model), FR3 (model), FR6
**FROZEN after this sprint:** main.py, models.py, schemas.py, exceptions.py, database.py, config.py, conftest.py.

## Sprint 002 — Notes CRUD
**Scope:** Notes router (POST /notes, GET /notes, GET /notes/{id}, PATCH /notes/{id}, DELETE /notes/{id}). All auth-required.
**FRs:** FR2 (routes), FR5
**Modified files:** none.

## Sprint 003 — Tags + Filter
**Scope:** Tags router (POST /tags, GET /tags, DELETE /tags/{id}). Notes router gets a tag-filter query param via... wait, that requires modifying notes.py. Alternative: separate /notes/by-tag/{tag_id} endpoint = pure-additive.
**FRs:** FR3 (routes), FR4
**Modified files:** none (uses /notes/by-tag/{tag_id} pure-additive endpoint).

---
```

(~30 lines. Validates the additive-only design — Sprint 003 deliberately picks a structure that doesn't require modifying sprint 002's notes.py.)

## Test 1: `design_phase` in isolation

**What we're testing:** Opus reads inputs and produces `.ai/contract.md` + `.ai/sprint_descriptions.jsonl`, then stops cleanly. No re-entry, no `write_enriched_sprint` calls (the tool isn't even available).

### Setup

```fish
set TESTDIR /tmp/struct_fix_test_design
rm -rf $TESTDIR; mkdir -p $TESTDIR/.ai
cd $TESTDIR
git init -q

# Drop in the synthetic spec_analysis.md and sprint_plan.md from this doc.
# (Will be created when this test runs; for now they're just templates.)
```

### Run

```fish
~/go/bin/tracker --no-tui --autopilot lax /Users/michaelsugimura/Documents/GitHub/pipelines/design_phase_only.dip
```

(`design_phase_only.dip` — a minimal dip with just `Start → setup_workspace → design_phase → Exit`. We'll write this when we ship the structural fix.)

### Pass criteria

- `.ai/contract.md` exists. Contains all 9 expected architect-prompt sections (Stack, Conventions, Data Model, Test Infrastructure, File-Ownership, Type Map, Dep Edges, Mandatory Rules, Tricky Semantics).
- `.ai/sprint_descriptions.jsonl` exists. Contains exactly 3 lines, each parsing to `{path: "SPRINT-NNN.md", description: str}` for N=001, 002, 003 in order.
- Each `description` field is non-empty and looks like a per-sprint slice (title, scope, FRs, file breakdown, validation).
- The activity log shows the agent making at most 2 `write` calls (one per file) and zero `write_enriched_sprint` calls.
- Total wall time: ≤ 90 sec.
- Total cost: ≤ $0.50 (Opus reasoning + 2 short writes).

### Fail signals

- 3+ `write` calls (Opus revising contract or descriptions multiple times) → architect prompt is still triggering re-review behavior; tighten stop rule.
- `write_enriched_sprint` appears in agent's tool list when it shouldn't → dip's tools-list config is wrong.
- Malformed JSONL (line that doesn't parse) → architect prompt's JSONL instruction needs stronger format constraint (give Opus the JSON schema).
- Missing description fields per the spec format → architect prompt's "what goes in each description" section needs more specificity.

### Validation script (simple)

```fish
# Lines should be 3, each valid JSON, paths zero-padded
python3 -c "
import json, sys
with open('.ai/sprint_descriptions.jsonl') as f:
    lines = [l for l in f if l.strip()]
assert len(lines) == 3, f'expected 3 lines, got {len(lines)}'
for i, line in enumerate(lines):
    d = json.loads(line)
    assert d['path'] == f'SPRINT-{i+1:03d}.md', f'line {i+1}: bad path {d[\"path\"]}'
    assert len(d['description']) > 200, f'line {i+1}: description too short'
print('OK')
"
```

## Test 2: `dispatch_sprints` in isolation

**What we're testing:** the new tracker tool reads a JSONL plan and calls `write_enriched_sprint` once per line. Mechanical loop. No LLM agency.

### Setup

```fish
set TESTDIR /tmp/struct_fix_test_dispatch
rm -rf $TESTDIR; mkdir -p $TESTDIR/.ai/sprints
cd $TESTDIR

# Use a known-good contract from a prior run (or hand-write a minimal one)
cp /Users/michaelsugimura/Documents/GitHub/pipelines/experiments/architect_pipeline_test_v8/.ai/contract.md .ai/

# Hand-write a 3-line JSONL with intentionally simple descriptions (smaller scope = cheaper test)
cat > .ai/sprint_descriptions.jsonl <<'EOF'
{"path":"SPRINT-001.md","description":"Sprint 001 — Core Foundation\n\nFront-load: 3 ORM models (User, Note, Tag), all schemas, AppError, JWT auth, /auth/signup + /auth/login + /health, full conftest.\n\nFROZEN files: main.py, models.py, schemas.py, exceptions.py, database.py, config.py, conftest.py.\n\nNew files: backend/pyproject.toml, backend/app/__init__.py, backend/app/main.py (auto-discovery), backend/app/config.py, backend/app/database.py, backend/app/exceptions.py, backend/app/models.py, backend/app/schemas.py, backend/app/auth.py, backend/app/dependencies.py, backend/app/routers/__init__.py, backend/app/routers/auth.py, backend/scripts/init_db.py, backend/tests/__init__.py, backend/tests/conftest.py, backend/tests/test_health.py, backend/tests/test_config.py, backend/tests/test_auth.py, backend/tests/test_models.py.\n\nModified files: none.\n\nValidation: cd backend && uv sync --all-extras && uv run pytest -v"}
{"path":"SPRINT-002.md","description":"Sprint 002 — Notes CRUD (additive)\n\nNew files only: backend/app/routers/notes.py, backend/tests/test_notes.py. Modified files: (none — main.py auto-discovers).\n\nEndpoints: POST/GET/GET-by-id/PATCH/DELETE on /notes, all auth-required.\n\nValidation: cd backend && uv run pytest tests/test_notes.py -v"}
{"path":"SPRINT-003.md","description":"Sprint 003 — Tags + tag-filter (additive)\n\nNew files only: backend/app/routers/tags.py, backend/tests/test_tags.py. Modified files: (none).\n\nEndpoints: POST/GET/DELETE on /tags + GET /notes/by-tag/{tag_id}. All auth-required.\n\nValidation: cd backend && uv run pytest tests/test_tags.py -v"}
EOF

set -gx TRACKER_SPRINT_WRITER_MODEL claude-sonnet-4-6
```

### Run

```fish
# Once dispatch_sprints is implemented, invoke it directly via tracker:
# (Tracker tool registration lets us call dispatch_sprints from a thin dip.)
~/go/bin/tracker --no-tui --autopilot lax /Users/michaelsugimura/Documents/GitHub/pipelines/dispatch_sprints_only.dip
```

### Pass criteria

- 3 files in `.ai/sprints/`: SPRINT-001.md (~700-1000 lines, foundation), SPRINT-002.md + SPRINT-003.md (~150-300 lines each, additive).
- Each SPRINT-NNN.md has the speedrun shape (Scope through Validation; Tricky semantics, Algorithm, Test contract, Verbatim files all present).
- The dispatch tool's return string shows: `dispatched 3 sprints, K with audit patches, 0 failures` (where K is 0-3 depending on how many audits found issues).
- Total wall time: 6-10 min for 3 sprints (each takes ~2-3 min for author + audit).
- Total cost: ~$1.50-2 (3 × $0.50 author/audit per sprint).
- No re-writes of `.ai/contract.md` (it was input only).

### Fail signals

- Any SPRINT-NNN.md missing → tool's loop is broken or per-sprint call failed silently.
- Tool reports failures > 0 → audit patch failed AND fallback failed (or some other internal error). Inspect the activity stream for the failing call.
- A SPRINT-NNN.md is < 100 lines → Sonnet was truncated or the audit corrupted output. Compare against author-pass tokens in activity stream.

### Failure-injection variants

Once the happy path passes, intentionally break inputs and verify the tool handles them:

- Corrupt one JSON line (introduce malformed JSON) → tool should report failure on that line, continue with the others, return error count = 1.
- Set one `path` to a non-`SPRINT-NNN.md` form → tool should refuse (path validation) before calling write_enriched_sprint.
- Empty `description` → tool should refuse (empty descriptions are unusable).

## Test 3: end-to-end synthetic (full pipeline)

**What we're testing:** the whole new pipeline (design → dispatch → ledger → validate) on the Notebook API synthetic project.

### Setup

```fish
set TESTDIR /tmp/struct_fix_test_e2e
rm -rf $TESTDIR; mkdir -p $TESTDIR/.ai
cd $TESTDIR
git init -q

# Copy the synthetic spec_analysis.md and sprint_plan.md (full text, not outlines)
# into .ai/. We'll author these as fixtures alongside this doc.
cp /path/to/synthetic-fixtures/notebook_spec_analysis.md .ai/spec_analysis.md
cp /path/to/synthetic-fixtures/notebook_sprint_plan.md .ai/sprint_plan.md
```

### Run

```fish
set -gx TRACKER_SPRINT_WRITER_MODEL claude-sonnet-4-6
~/go/bin/tracker --no-tui --autopilot lax /Users/michaelsugimura/Documents/GitHub/pipelines/architect_only_test.dip
```

(After the structural fix, `architect_only_test.dip` will use the new design_phase + dispatch_sprints pattern.)

### Pass criteria

- Both stage outputs produced: `contract.md` (~600-900 lines for a 3-entity project), `sprint_descriptions.jsonl` (3 lines).
- All 3 SPRINT-NNN.md files produced at expected sizes.
- `validate_output` passes (each spec has Scope, Non-goals, DoD, Validation).
- `ledger.tsv` has 3 rows, all `planned`.
- Activity log: zero `write` calls after `design_phase` agent terminates (agent should have exited cleanly without re-entry).
- Total wall time: 8-12 min (design ~2 min, dispatch ~6-9 min for 3 sprints).
- Total cost: ~$2-3.

### Verification beyond just "files exist"

For each output, run a structural check:

#### `contract.md` checklist (run via grep)

```fish
grep -E "^## " .ai/contract.md | sort > /tmp/sections.txt
diff /tmp/sections.txt <(echo "## 1. Stack & Runtime
## 2. Project-wide Conventions
## 3. Data Model Pinning (Cross-Sprint)
## 4. Test Infrastructure
## 5. Sprint File-Ownership Map
## 6. Cross-Sprint Type/Symbol Ownership Map
## 7. Cross-Sprint Dependency Edges
## 8. Mandatory Rules Across All Sprints
## 9. Tricky Semantics" | sort)
# Empty diff = pass
```

Plus content checks: `grep -cE 'lazy=\"selectin\"|StaticPool|FROZEN|AppError|pkgutil' .ai/contract.md` should be ≥ 5.

#### `SPRINT-001.md` checklist

- ≥ 600 lines
- Contains `pkgutil.iter_modules` (auto-discovery main.py)
- Contains `lazy="selectin"` on collection-side relationships
- Contains `StaticPool` in conftest spec
- Contains 3 ORM models (User, Note, Tag) with full field definitions
- Contains `AppError` class definition + error code constants
- Has all sections: Scope, Non-goals, Dependencies, Conventions, Tricky semantics, Interface contract, Algorithm, Test plan, Verbatim files, New files, Modified files, Rules, DoD, Validation

#### `SPRINT-002.md` and `SPRINT-003.md` checklist

- ≤ 300 lines each (additive sprints are small)
- Contains `## Modified files: (none ...)`
- Path/query parameters typed as `uuid.UUID` (not `str`)
- Test asserts use `body["error_code"]` (matches contract.md's flat handler shape)
- Routes use empty path `""` (not `"/"`) for collection routes

### Acceptance gate

If Tests 1 + 2 + 3 all pass on the synthetic project, the structural fix is ready for NIFB acceptance testing.

## Test 4: NIFB acceptance test

Once the synthetic project goes green, repeat against NIFB's full inputs (`experiments/NIFB/.ai/spec_analysis.md` + `sprint_plan.md`). 16 sprints, ~$4-5 cost, ~30-40 min. Validates the structural fix scales beyond the toy fixture.

### Pass criteria

- All 16 sprint specs produced.
- contract.md ≥ 800 lines with all 9+ sections.
- Each SPRINT-NNN.md matches the speedrun shape.
- No `write` calls after `design_phase` terminates.
- Compare 5 randomly-sampled sprint specs against [`exemplars/`](exemplars/) for shape parity.

### Optional: run sprint 001 through the qwen runner

The full chain: design → dispatch → qwen runner → tests pass. If sprint 001 generates 20+ files and pytest passes 21+ tests on first try, the architect+writer side is producing specs the local generator can actually consume. This is the gold-standard end-to-end test.

This is what we already validated manually on Apr 30 (v7 SPRINT-001 hand-written → 21/21 tests). If the new pipeline produces equivalent output, we've proven the architect-side automation works.

## What this test plan does NOT cover

- Parallelization of `dispatch_sprints` — out of scope for v1; tests assume sequential.
- Resumability after partial failure — would need a separate failure-injection test once we add the resume capability.
- Prompt-cache optimization (caching contract.md across the 16 dispatch calls) — future work; tests don't depend on it.
- Multi-language projects (Go, TS) — synthetic fixture is Python-specific. Future test variants can swap stacks.

## Recommended order

1. **Build dispatch_sprints + tactical Opus prompt patch** — minimal viable structural change.
2. **Author the synthetic Notebook API fixtures** (spec_analysis.md + sprint_plan.md) and commit them to `experiments/sprint_authoring_principles/synthetic_fixtures/`.
3. **Run Test 1** (design_phase isolated) on synthetic → debug Opus prompt as needed.
4. **Run Test 2** (dispatch_sprints isolated) on hand-written JSONL → debug tool as needed.
5. **Run Test 3** (end-to-end synthetic) → confirm the full pipeline works on a small project.
6. **Run Test 4** (NIFB acceptance) → confirm scale.
7. **Optional Test 5** (qwen runner end-to-end) → confirm the chain holds.

Each step is gated on the previous passing. If a step fails, fix that piece before moving on.

## Estimated cost & time for the full test suite

| Test | Time | Cost |
|---|---|---|
| Test 1 (design isolated) | 1-2 min | $0.30-0.50 |
| Test 2 (dispatch isolated) | 6-10 min | $1.50-2 |
| Test 3 (end-to-end synthetic) | 8-12 min | $2-3 |
| Test 4 (NIFB acceptance) | 30-40 min | $4-5 |
| Test 5 (qwen runner) | +12-15 min | $0 (local qwen) |
| **Total** | **~1 hr** | **~$8-11** |

Iteration cost (re-running Tests 1-3 after a bug fix) is ~$3-5 / 15 min, which is the right cadence for tight iteration.
