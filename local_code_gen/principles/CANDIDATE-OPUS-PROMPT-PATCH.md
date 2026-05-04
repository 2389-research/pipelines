# Candidate Opus prompt patch — `spec_to_sprints.dip:537` `write_sprint_docs` agent

Replacement / extension text for the `write_sprint_docs` agent prompt in `spec_to_sprints.dip`. This is the staging surface — when this lands, `git diff` it into the dip and validate.

The current prompt is at `pipelines/spec_to_sprints.dip:537–618` (read it before applying this patch). It already has good bones: the architect's job, the contract.md authoring step, the per-sprint iteration via `write_enriched_sprint`. The patch adds:

1. The architect_v2 design choice (front-load + auto-discover + freeze) as the default architectural pattern
2. The cross-sprint patterns (O-1 through O-8) to be encoded in contract.md
3. The architect-discipline meta-rules

The intent is **not** to enumerate the 14 defect classes — Opus uses judgment. The intent is to give Opus a small, well-described set of categories with examples so it can recognize and close gaps that fall in those categories.

---

## Patch — text to embed in the prompt body

(Drop after the existing "Inputs:" / "Step 1: Read both input files" sections. Replace the existing "Step 2: Author the project-wide contract" section with this expanded form. Keep everything from "Step 3: For each sprint in the plan, call `write_enriched_sprint`" onward intact.)

```
## Step 2: Author the project-wide contract → write to `.ai/contract.md`

The contract is the cross-sprint architectural surface — pinned ONCE for the entire project,
read by every per-sprint generation call. The local model that ultimately writes code from
SPRINT-NNN.md cannot make architectural decisions, look up library docs, or resolve
ambiguity. Every cross-sprint convention must be pre-decided and pinned here.

A well-written contract leaves the per-sprint writer (Sonnet) zero choices about
project-wide concerns. Sonnet's job is to expand within-sprint specifics; the architect's
job is to lock in cross-sprint conventions.

### Architectural pattern: front-loaded foundation (default for typical web-API projects)

Default to this architecture unless the project shape doesn't fit it:

1. **Sprint 001 declares the entire surface area:** every ORM model + every Pydantic
   schema + every error code constant + every test fixture + the FastAPI/equivalent
   app factory. After sprint 001, a fixed list of foundation files is FROZEN — no
   later sprint modifies them.

2. **Auto-discovery in `main.py`:** the app factory uses `pkgutil.iter_modules(...)`
   (or framework-equivalent) to scan the routers/ directory and auto-register any
   module that exposes a `router` attribute. Sprints 002+ drop a new file in
   `routers/<feature>.py` and it auto-registers. `main.py` is FROZEN.

3. **FROZEN files list (declared explicitly in contract.md):** `app/main.py`,
   `app/models.py`, `app/schemas.py`, `app/exceptions.py`, `app/database.py`,
   `app/config.py`, `tests/conftest.py`. The only foundation file later sprints
   may modify is `pyproject.toml` (or equivalent) to append new dependencies.

4. **Sprints 002+ are purely additive:** their `## Modified files` section reads
   "(none)". They drop new files in `routers/` and `tests/`; that's it.

This pattern eliminates the cross-sprint patch fragility we hit before. It requires
sprint 001 to be larger (~600-1000 line spec for a non-trivial project) but every
later sprint becomes ~200-300 lines and patch-loop-clean.

If the project doesn't fit this pattern (e.g., truly unknown data model that emerges
sprint-by-sprint), make the architectural choice explicit in contract.md and document
the alternative.

### Required sections in `.ai/contract.md`

Author all of these. Each must be precise enough that Sonnet's per-sprint expansion
inherits unambiguous conventions.

#### 1. Stack & Runtime

- Language(s) and version
- Package manager and key third-party libraries — with exact import names
- Anything explicitly excluded
- The build-system block REQUIRED for the chosen package manager (e.g., for hatchling
  with project name ≠ package dir name: `[tool.hatch.build.targets.wheel] packages =
  ["<dir>"]` is mandatory; auto-detection fails without it)

#### 2. Project-wide Conventions

- Error handling idiom — including the EXCEPTION CLASS and the JSON RESPONSE SHAPE
  it returns. If the project uses a custom exception (e.g., `AppError`) with a
  flat `{"detail": str, "error_code": str}` handler, pin BOTH the class signature
  AND the wire shape. Every sprint's tests will assert against the wire shape.
- Naming conventions (file/module casing, test file naming)
- Test framework + test organization rules
- Async vs sync, logging conventions

#### 3. Data Model Pinning (cross-sprint)

For ORMs with async semantics, pin the loading strategy explicitly:
- Async loading: collection-side relationships use `lazy="selectin"` (or analog)
- Bidirectional relationships use `back_populates` on BOTH sides

For Pydantic v2 settings: pin the singleton pattern and forbid class-attr access.
Tests use literal values for config-derived constants; `Settings.X` is forbidden
(Pydantic stores fields on instances, not class attributes — class-attr access
raises `AttributeError`).

#### 4. Test Infrastructure

Pin the test fixture and engine configuration. The conftest.py lives in the
foundation sprint and is referenced by every later sprint.

For in-memory SQLite tests:
- `create_async_engine("sqlite+aiosqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool)`
- Without StaticPool, every connection gets its own in-memory DB; cross-session
  writes are invisible.

For dependency override fixtures: helpers that reference fixture-resolved values
(e.g., `override_get_db` referencing `async_engine`) MUST be defined as nested
closures inside the consuming fixture, NOT at module level. Module-level definitions
bind to the pytest fixture decorator object, not the resolved value.

#### 5. Sprint File-Ownership Map

For every sprint in the plan, list the files it owns. **Apply the front-loaded
foundation pattern.** Sprint 001 owns everything; sprints 002+ are purely additive.

If the architecture genuinely can't fit this pattern, declare the alternative
explicitly with the modify-pattern (e.g., "Sprint 001 OWNS models.py; Sprint 002+
APPENDS new model classes only — never edits existing ones").

#### 6. Cross-Sprint Type/Symbol Ownership Map (load-bearing)

For every type, function, or constant that crosses sprint boundaries, declare:
- The owning sprint
- The exact signature: field names with types, function signatures with return types,
  relationship declarations including `back_populates` and `lazy="selectin"` annotations
- Where it's defined (file path)

This pins what later sprints will import. Underspecification here is the failure
mode — when the per-sprint writer doesn't see exact field names, it invents and
diverges across sprints.

#### 7. Cross-Sprint Dependency Edges

Directed graph of which sprints depend on which.

#### 8. Mandatory Rules Across All Sprints

Project-wide rules that every sprint inherits. Include:
- Import conventions (`from app.X import Y` form; no relative imports; full
  Python statements never bare module names; for class-vs-module collisions
  like `datetime`/`date`/`time`, use `from X import Y` explicitly)
- The FROZEN files list (no later sprint may modify these)
- The test-fixture-from-conftest rule (no inline AsyncClient/engine/session
  construction in test files)
- The decisive-choice rule: where the spec is ambiguous, contract.md commits
  to one answer

#### 9. Identify the project's *tricky semantics*

Areas where convention matters and silence forces the implementer to guess.
Common categories: concurrency/loading model, resource lifecycle, process-global
state, paired cross-module invariants, config defaults + test override. Document
the chosen pattern for each.

### Architect-discipline meta-rules to apply when authoring contract.md

- **Structural sections must embody structural rules.** When contract.md states
  a structural rule (route order, field order, declaration order), the structured
  sections (tables, signatures, algorithm subsections) must reflect it. The
  local generator follows structure, not prose. If the rule and the structure
  conflict, the structure wins.

- **Make concrete choices.** Where the upstream spec is ambiguous, contract.md
  commits to one answer. Don't hedge with "you may use X or Y." Don't write
  "choose based on your preference."

- **Pin exact field sets.** When defining a schema or model, list every field
  with its type. Never write a partial example with "...etc." The local generator
  invents fields when given an incomplete shape.

- **Cross-reference the runtime symptom.** When pinning a non-obvious convention
  (e.g., StaticPool, lazy="selectin"), include a one-liner about WHAT FAILS
  WITHOUT IT. The Sonnet writer reads contract.md and applies these conventions
  per-sprint; knowing the failure mode helps it judge edge cases.

Save the contract to `.ai/contract.md` using the write tool.
```

---

## Notes on what's already good in the existing prompt

The existing prompt has these elements that I'd preserve:

- The "tricky semantics" framing under Mandatory Rules (already there from earlier work)
- The front-loaded-foundation paragraph in Sprint File-Ownership Map (already there from earlier work)
- The infrastructure & setup specifics paragraph for Sprint 001's pyproject.toml (already there)
- The "Cross-Sprint Type/Symbol Ownership Map (load-bearing)" framing
- Step 3+: per-sprint iteration via `write_enriched_sprint` calls (untouched)

What this patch ADDS to the existing prompt:

- The architect_v2 design pattern as the explicit default
- The 4 expanded contract.md sections (Stack & Runtime build-system; Project-wide error/handler shape; Data Model async loading; Test Infrastructure)
- The 4 architect-discipline meta-rules at the end

## Notes on what NOT to embed

- The 14 defect classes — keep in [`DEFECT-CLASSES.md`](DEFECT-CLASSES.md) as the empirical record / appendix. Opus doesn't need to memorize them.
- The exemplar SPRINT-NNN.md files — too token-heavy for a prompt. They're for human reference and could optionally be referenced via path if Opus needs to peek.
- Stack-specific examples (e.g., FastAPI's `pkgutil.iter_modules` exact code) — keep generic in the prompt; let Opus apply to the project's specific stack via the upstream spec.

## How to apply

```bash
# Read current
sed -n '537,620p' /Users/michaelsugimura/Documents/GitHub/pipelines/spec_to_sprints.dip

# Apply the diff (manually — replace Step 2 in the agent prompt body)

# Validate
~/go/bin/tracker validate /Users/michaelsugimura/Documents/GitHub/pipelines/spec_to_sprints.dip
```

After applying, the test is end-to-end: regenerate NIFB sprints from the updated prompt and check that contract.md ends up with the expected pinning + the per-sprint outputs match the speedrun format. See `README.md` § How to test.
