# Findings — sprint enrichment + local-LLM execution (Apr 2026)

End-of-session retrospective on what we tested, what worked, and what's still unsolved. Pick up here next session.

## Pipeline structure (built and validated)

**Generation side (architect → Sonnet) — works well.**

- `spec_to_sprints.dip` patched: `write_sprint_docs` agent uses Opus as architect; iterates sprint-by-sprint calling `write_enriched_sprint` (per-file mode); tool reads `.ai/contract.md` from disk
- Tool `write_enriched_sprint` (in tracker repo): single-sprint per call, Sonnet as generator, system prompt embeds reference example + verbatim-content rule for non-code files
- Architect prompt enforces: cross-sprint type/symbol ownership map with exact field names; per-sprint New/Modified file split; verbatim infrastructure config (pyproject.toml, build-system, tsconfig, etc.)
- Cost ~$3.30 / 30 min for 16-sprint NIFB run
- Cross-sprint coherence: validated — exception hierarchy, import paths, type names all consistent across sprints

**Execution side (qwen runner) — partially works, not reliable end-to-end.**

- `sprint_runner_test.dip` patched: proj_root detection, `uv sync --all-extras`, `uv run pytest > file 2>&1; code=$?` (no PIPESTATUS), bumped timeouts (Generate 3600s, LocalFix 900s)
- `patch_file` upgraded with validation guards (line-count floor, pre-symbol preservation, syntax check), in-memory rollback on validation failure, retry-with-feedback up to 10 attempts, escalation to CloudFix on exhaustion
- Standalone test (`test_patch_flow.sh`) confirms validation + retry-with-feedback works in isolation when context is tight (~1KB)

## Sprint-design patterns explored

### V1: Incremental APPEND (current production shape)

Sprints 002+ patch sprint 001's `models.py`, `schemas.py`, `main.py`. Catastrophic failure: qwen wrote the file *path* as the file's full content during patch_file → wiped sprint 001's models. Even after validation guards prevented the silent overwrite, qwen retries on the same blind spot didn't recover; CloudFix could only partially reconstruct from a broken baseline.

Empirical result against runner_test (5 sprints): all marked completed, but actual pytest at end showed 22 failed / 48 errors / 19 passed. The runner's prior "tests-pass" detection bug (PIPESTATUS) masked failures.

### V2: Front-loaded foundation (this session's primary design proposal)

Sprint 001 carries the FULL data model, all Pydantic schemas, all test fixtures, all error codes, plus auth feature. Sprints 002+ are pure additive — only new router/service/test files. `main.py` uses `pkgutil.iter_modules` to auto-discover routers; never modified. Zero `## Modified files` entries across all 5 sprints.

**Designed**: 5 NIFB sprints in `architect_v2/.ai/sprints/` (~2350 lines total vs ~5K+ for v1).

**Empirical result against runner_test_v2**:
- Sprint 001: completed after 4 LocalFix + 5 CloudFix (~25 min, all green at end)
- Sprint 002: **failed — exhausted max_restarts (50)**. Hit ~30+ consecutive CloudFix calls that each completed but RunTests immediately failed again
- Total cost: ~$0.50 OpenAI for cloud fix loops (1M input / 129K output)

**What worked**: Sprint 001 produced cleanly via gen_file (no patches). Foundation files all written.

**What didn't work**: Sprint 002, despite being pure-additive (no patches needed), entered an endless CloudFix loop. Cloud kept "fixing" something that immediately broke under retest. Likely cause: subtle issue in sprint 001's foundation (untested by sprint 001's own test suite that passed) propagated to sprint 002's tests, and CloudFix kept oscillating around the wrong target without seeing the spec.

So front-loading **eliminated patch fragility** but exposed a different fragility: when CloudFix can't see the spec, it diagnoses-by-inference and gets stuck.

## Design principles identified

1. **Local model is a transcriber, not a designer.** Every file in `## New files` MUST have its complete literal content somewhere in the spec — either in `## Interface contract` + `## Algorithm notes` for code, or in `## File contents` (verbatim fenced block) for trivial/config files.

2. **Validation + rollback beats retry.** The runner's `patch_file` validation guards (line count, symbol preservation, syntax check) catch bad qwen output reliably. In-memory rollback to pre-edit state is the foundation; retry-with-feedback is bonus.

3. **Front-loading kills patch fragility but introduces foundation fragility.** Models/schemas/conventions defined once at sprint 001 cannot regress, but bugs in the foundation cascade silently to all later sprints. Sprint 001 needs *more* test coverage than we gave it (we wrote 21 tests; should be 50+ covering every model's CRUD and FK behavior).

4. **Cloud fix needs the spec, not just the failing test.** Today the CloudFix prompt sees: current (broken) file + test output + 3-step rule. It does NOT see the sprint spec or the pre-edit baseline. Result: cloud reconstructs by inference and oscillates. Critical fix: feed CloudFix the relevant sprint spec section + the pre-validation file (rolled-back via git or in-memory snapshot).

5. **The sprint runner is the hardest part of the system, not the generator.** Architect+Sonnet produces high-quality specs reliably. Qwen produces correct code most of the time when context is tight. The orchestration layer (when to retry, what to feed cloud, when to escalate, when to halt) is where complexity and fragility live.

## What's still unsolved

| Issue | Status |
|---|---|
| Endless CloudFix loops (sprint 002 in v2 run) | Not yet root-caused — need single-sprint diagnostic test |
| Per-file context slicing (qwen sees full sprint instead of file-relevant sections) | Designed in PROPOSED-CHANGES.md, not built |
| CloudFix lacks spec context | Identified; runner prompt needs upgrade to inject sprint spec + pre-edit baseline |
| Sprint 001's foundation tests insufficient coverage | Need richer model unit tests, FK constraint tests, schema round-trip tests |
| Cross-sprint test regression detection | Audit currently only counts files + tests; doesn't run prior-sprint test suite to confirm no regressions |
| Pipeline halt on real test failure | RunTests `$?` fix is in; needs verification it propagates through Audit correctly |

## Next test plan: single-sprint isolation

Goal: diagnose where the fragility lives by reducing to one sprint at a time and observing outputs closely.

### Phase 1: Foundation sprint alone
- Use `architect_v2`'s sprint 001 spec
- Run runner against ONLY sprint 001 (003-016 marked skipped, 002 marked skipped initially)
- Goal: get sprint 001's pytest 100% green with zero CloudFix calls
- If it doesn't pass with zero cloud fix:
  - Inspect qwen's output for each file vs the spec
  - Identify which guards (validation/syntax/symbol) catch the issue or fail to
  - Iterate on sprint 001 spec until qwen produces clean code first try

### Phase 2: Additive sprint on a known-good base
- Foundation from Phase 1 committed
- Run sprint 002 alone, foundation from disk
- Goal: 4-8 new files from gen_file, all tests green
- If CloudFix fires:
  - Read CloudFix's actual fixes — what's it changing?
  - Identify whether the issue is qwen, cloud, spec under-specification, or something else

### Phase 3: Two-sprint chain
- Once 001 and 002 individually clean
- Run them as a pair, verify Sprint 002's tests don't break Sprint 001's
- If breaks: pin the regression to a specific qwen output

### Phase 4: Per-file context slicing
- Implement awk-based extraction in runner (proposed in PROPOSED-CHANGES.md)
- Re-run Phase 1 with sliced context, observe whether qwen first-try success rate improves
- Hypothesis: smaller context → fewer hallucinations

### Phase 5: CloudFix prompt upgrade
- Inject sprint spec + pre-edit baseline into CloudFix prompt
- Re-run Phase 2
- Hypothesis: cloud's "diagnose by inference" failure goes away

## What we have on disk

- **Pipelines repo branch `feat/enriched-sprints-test`** at commit `a32f553` — production patch + test pipelines + this notes file
- **Tracker repo branch `feat/write-enriched-sprint-tool`** at commit `b2bca6b` — `write_enriched_sprint` tool + registration
- `experiments/enrich_sprints_test/architect_v1/` — incremental-APPEND specs (v1 design)
- `experiments/enrich_sprints_test/architect_v2/` — front-loaded specs (v2 design)
- `experiments/enrich_sprints_test/runner_test/` — v1 runner test workdir, sprints 001-005 marked completed (22 fail / 48 errors at end)
- `experiments/enrich_sprints_test/runner_test_v2/` — v2 runner test workdir, sprint 001 completed; sprint 002 exhausted max_restarts
- `experiments/enrich_sprints_test/test_patch_flow.sh` — standalone validation+retry test (passing)
- `experiments/enrich_sprints_test/PROPOSED-CHANGES.md` — per-file context slicing design
- `MIGRATION-enriched-sprints.md` — production migration doc

## Quick dollar/time tally

| Phase | Run | Cost | Time |
|---|---|---|---|
| Architect+Sonnet generation | 16 sprints | ~$3.30 | 30 min |
| Opus-only enrichment (comparison) | 16 sprints | ~$5.84 | 18 min |
| V1 runner — 5 sprints | 5/5 marked complete (broken) | ~$0.30 | 56 min |
| V2 runner — 5 sprints | 1/5 complete, halt at sprint 002 | ~$0.50 | 70 min |

Total session burn: ~$10. Cheap relative to a single human-day on this work.

---

## Update — Apr 29 session: Phase 1 isolation probe (qwen-only, no CloudFix)

Rebuilt the test methodology to isolate single-sprint behavior. Workdir: `qwen_probe/runs/03_full_cycle/`. Spec: `architect_v2/.ai/sprints/SPRINT-001.md` (front-loaded foundation, 1253 lines).

### Pipeline shape (`probe_full.sh`)

1. Parse `## New files` from sprint spec
2. **Touch (no LLM)** files whose description bullet contains `empty|blank|placeholder|marker` — 4 of 4 init files
3. **Generate** the remaining 16 via qwen (one Ollama call per file, `temperature=1.0, top_p=0.95, top_k=64`, no `presence_penalty`)
4. `uv sync --all-extras` then `pytest`
5. While failing and rounds < 8: ask qwen which file is broken → ask qwen to rewrite that file → re-test

### Result: ✅ 21/21 tests pass, 5 patch rounds, ~26 min, $0

| Round | qwen picked | bytes pre→post | pass / fail / err | Δ pass |
|---|---|---|---|---|
| 0 | (initial gen, all 16 files) | — | 17 / 4 / 0 | baseline |
| 1 | tests/test_models.py | 13302 → 13324 | 17 / 4 / 0 | 0 |
| 2 | app/models.py | 13473 → 13809 | 2 / 16 / 3 | **−15** ⚠️ |
| 3 | app/models.py | 13809 → 14393 | 18 / 3 / 0 | **+16** ↑ |
| 4 | tests/test_models.py | 13324 → 14059 | 18 / 3 / 0 | 0 |
| 5 | tests/test_models.py | 14059 → 14010 | **21 / 0 / 0** ✅ | +3 |

### Round 2 regression mechanism (the textbook case for surgical edits)

Round 2 was full-file rewrite of `app/models.py` to address two `MissingGreenlet` failures (async lazy-load on relationships). qwen added `back_populates="X"` to the **forward side** of 5 relationships across `Station`, `Registration`, `Group`, `GroupMember`, `Assignment` — but did NOT touch the reverse-side classes (`Volunteer`, `Location`, `Shift`). SQLAlchemy requires both sides declare matching `back_populates`; half-declared metadata throws on the first session use → 15 previously-passing tests broke instantly.

Plus a cross-class typo: `Shift.location → relationship(back_populates="stations")`. Should reference `Location.shifts`. Round 3 corrected it.

Round 3 (full-file rewrite again of `models.py`) added 8 matching list relationships:
- Volunteer: `registrations`, `groups`, `group_members`, `assignments`
- Location: `shifts`
- Shift: `assignments`
- Station: `assignments`
- Plus the back_populates typo fix

That's the recovery: qwen had to make a coherent multi-class change and only saw it all at once via full-file rewrite.

### Hyperparam exploration

Tested vendor-recommended Qwen3.6 settings against current. No improvement on the empty-init failure mode.

| Pass | Settings | syntax-pass | failure |
|---|---|---|---|
| 01 baseline | `top_k=64` | 19/20 | `routers/__init__.py` ` ```python ``` ` (fenced empty file) |
| 02 recommended | `top_k=20`, `presence_penalty=1.5` | 18/20 | same fence + new docstring quote bug in `exceptions.py` |

Conclusion: empty-file generation is invariant to hyperparams. It's a spec/runner architecture issue. Reverted to `top_k=64`. Probe 03 used the **runner-level** fix (touch the file, skip the LLM call entirely when description marks it empty).

### Validated design principles

1. **"Empty file" detection works generically.** Description-tail keyword match (`empty|blank|placeholder|marker`) caught all 4 init files in this sprint. Architect prompt should emit empty files into a dedicated `## Empty files` section for zero-ambiguity parsing — runner-side change is `: > "$path"` per entry.

2. **Single-sprint isolation eliminates the catastrophic failure mode.** Every prior multi-sprint run hit some form of cross-sprint state corruption (V1 wiped models.py mid-stream, V2 sprint 002 ate max_restarts). Sprint 001 alone converges cleanly with pure qwen.

3. **Full-file rewrite is recoverable but expensive.** Round 2's −15 regression cost 3 min wall time and required round 3's coordinated multi-class rewrite to recover. SEARCH/REPLACE-style surgical edits would strictly dominate: changes scale with edit size not file size, partial changes can't half-corrupt metadata, and failed merges fail loudly (block doesn't match) instead of silently breaking unrelated tests.

4. **Don't escalate to CloudFix prematurely.** The v2 runner kicked CloudFix in after 4 LocalFix attempts. The probe needed 5 rounds to converge — escalating mid-recovery (after the round-2 disaster) would have given cloud a corrupted baseline and triggered the "CloudFix oscillates without spec context" failure we saw in the v2 sprint 002 hang. Recommendation: bump local attempt budget to ≥8 before cloud handoff, OR detect "regression then partial recovery" and trust the local loop to finish.

5. **qwen self-corrects across rounds.** Despite picking the wrong file in round 1 (test instead of source) and producing a regressing rewrite in round 2, qwen recovered without any external nudge. The fix-then-test feedback loop is the actual signal that drives convergence — not the in-prompt feedback.

### What's still on the table

| Issue | Status |
|---|---|
| `## Empty files` spec section + runner support | Designed, not built |
| SEARCH/REPLACE patch format with fuzzy merger (Aider-style) | Researched (Aider has empirical wins on local models); not built |
| CloudFix prompt missing spec + pre-edit baseline | Identified earlier; still unbuilt |
| Architect-side: define `back_populates` pairs explicitly so qwen doesn't infer them | New finding from round 2 — spec underspecified the relationship symmetry |
| Two-sprint chain test (Phase 3 from original plan) | Not yet run; should validate single-sprint isolation extends across additive sprints |

### Apr 29 dollar/time tally

| Phase | Wall time | Cost |
|---|---|---|
| Probe 01 baseline (gen-only, 20 files) | 10 min | $0 |
| Probe 02 recommended (gen-only, 20 files) | 10 min | $0 |
| Probe 03 full cycle (gen + 5 patch rounds + tests) | 26 min | $0 |

All-local. Comparison point: the v2 runner_test_v2 multi-sprint run earlier this week burned ~$0.50 OpenAI on CloudFix and still didn't converge on sprint 002.

---

## Update — Apr 30 session: pipeline-validated speedrun spec format + 14 defect classes

End-to-end pipeline validation. The v2 front-loaded design works. The local-only execution with one LocalFix round suffices. The CloudFix-loop failure mode from earlier (V2 sprint 002 oscillation) is closed by spec-side rules, not by smarter cloud diagnosis.

### Result: 21/21 + 47/47 cumulative on first generation pass (sprint 001 + 002 through the production runner)

| Sprint | Generate | LocalFix needed | CloudFix needed | Final |
|---|---|---|---|---|
| 001 | 5m56s, 20 files | No | No | 21/21 first try |
| 002 | 2m28s, 8 files | **Yes — 1 round, 2 SR blocks (test phone-collision)** | No | 47/47 cumulative |
| 003 | (pending pipeline run; specced and manually validated 14/14) | - | - | - |

LocalFix on sprint 002 caught a real qwen mistake: the test seeded N volunteers with the same hardcoded phone (`"1234567890"`) which violates `unique=True`. qwen's SR call diagnosed the duplicate-phone IntegrityError and emitted two SR blocks changing it to `f"1234567890_{uuid.uuid4().hex}"`. Single round, clean merge, RunTests passed. **First time the patch loop has converted a real production-shape failure to passing in production-runner mode** (bench had only synthetic breaks before).

### Spec format: speedrun-style validated to scale

Three sprints designed in this format, each generated cleanly. The format is:

- `## Scope`, `## Non-goals`, `## Dependencies` — terse, factual
- `## Conventions` — project-wide rules inherited from sprint 001 in later sprints
- `## Tricky semantics` — load-bearing rules read FIRST. Lists conventions that without explicit pinning would force the local model to guess (async loading strategy, fixture closure scope, response-shape convention, etc.)
- `## Data contract` — every Pydantic model + ORM model with **full field signatures** but no method bodies (no `def`/`async def` bodies). Relationships pinned with `lazy="selectin"` and `back_populates` on both sides.
- `## API contract` — route table: method, path, request schema, response schema (status), errors (status + error_code).
- `## Algorithm` — per-route step-by-step prose. Numbered steps, explicit error raises with status_code/error_code/message. Not code, not pseudocode — natural language constrained to the contract types.
- `## Test contract` — per-test table: action, asserts. Includes fixture parameters explicitly.
- `## Verbatim files` (small, data-shaped files where exact text matters): `pyproject.toml`, `main.py` (the auto-discovery factory), `app/exceptions.py` (small AppError + error code constants), `init_db.py`. Full text fenced.
- `## New files` — bullet per file with EXACT imports list (full Python statements, never bare module names) + a one-line role summary referencing the contract sections.
- `## Modified files` — empty for sprint 002+ (additive only).
- `## Rules` — negative constraints + positive reinforcements of tricky-semantic rules (so they appear in two places, not just once).
- `## DoD` — machine-verifiable check items (exact bash invocations or "X passing tests").
- `## Validation` — exact bash sequence to verify the sprint.

Sprint sizes hit:
- SPRINT-001 (foundation, 18 entities, all schemas, full conftest): ~825 lines
- SPRINT-002 (additive: 4 routers + 4 test files): ~196 lines  
- SPRINT-003 (additive: 3 routers + 3 test files): ~239 lines

### Architect_v2 design (front-loading + auto-discovery + FROZEN files) — VALIDATED

The pattern works. Sprint 001 carries every model + every schema + every error code constant + the FastAPI app factory with `pkgutil.iter_modules` router auto-discovery. Sprints 002+ drop a single new file in `app/routers/<feature>.py` and it gets registered automatically — zero `## Modified files`. Cumulatively across 3 sprints: **0 modifications to any sprint 001 file**. This is what eliminates the V1 patch-fragility we hit earlier.

Sprint 001's FROZEN file list (declared in its Rules section, enforced as architect-level invariant):
- `app/main.py` — auto-discovers routers, never edited
- `app/models.py` — every entity, never edited
- `app/schemas.py` — every Pydantic schema, never edited
- `app/exceptions.py` — AppError + error code constants
- `app/database.py` — Base + lazy `get_engine()` + `get_session_factory()` + `get_db`
- `app/config.py` — Settings + cached `get_settings()`

Only foundation file later sprints may modify: `pyproject.toml` (to append new deps).

### 14 defect classes — runtime errors that map directly to spec gaps

These are the categories of "qwen makes a reasonable inference that breaks at runtime" we hit and closed during this session. Each one has: a category name, a runtime symptom, and a spec rule that closes it.

| # | Defect | Symptom | Spec rule that closes it |
|---|---|---|---|
| 1 | Hatchling build-system block missing `[tool.hatch.build.targets.wheel]` when project name ≠ package dir name | `uv sync` crashes during editable install before any test runs | Build-system blocks must enumerate per-backend config explicitly. For hatchling: `packages = ["<dir>"]`. |
| 2 | Bare module name in imports list (`datetime` instead of `from datetime import datetime`) | `MappedAnnotationError: ... is not a Python type, it's the object <module 'datetime'>` at SQLAlchemy mapping time | Imports are full Python statements. For class-vs-module collisions (`datetime`, `date`, `time`, `decimal.Decimal`), use `from X import Y` form. |
| 3 | Test references `Settings.OTP_BYPASS_CODE` (class-attr access on Pydantic v2 `BaseSettings`) | `AttributeError: OTP_BYPASS_CODE` (Pydantic stores fields on instances, not class attrs) | Tests use literal values for config-derived constants. If a test must read live config, instantiate `Settings()` and read the instance attribute. Class-attr access (`Settings.X`) on BaseSettings is forbidden. |
| 4 | Test constructs its own `AsyncClient`/engine/session inline | Various — broken httpx API kwargs, per-test isolation violations, stale state | Tests take fixtures (`client`, `db_session`, `volunteer_factory`) as function parameters. `conftest.py` is the single point of test setup; per-test self-sufficiency is forbidden. |
| 5 | Async ORM collection-side relationship missing `lazy="selectin"` | `sqlalchemy.exc.MissingGreenlet: greenlet_spawn has not been called` on `obj.collection` access | Every collection-side `relationship(...)` MUST include `lazy="selectin"`. List the affected relationships explicitly so qwen can't omit any. |
| 6 | Fixture-dependent helper defined at module level (e.g., `override_get_db` outside the `client` fixture) | `sqlalchemy.exc.ArgumentError: AsyncEngine expected, got <pytest_fixture(...)>` (helper bound to fixture decorator instead of resolved value) | Helpers that reference fixture-resolved values must be defined as nested closures INSIDE the consuming fixture. Spec must explicitly say "defined inside the fixture body, NOT at module level." |
| 7 | Path/query parameter typed as `str` instead of the actual Python type | `AttributeError: 'str' object has no attribute 'hex'` from SQLAlchemy's UUID column bind processor | API contract must specify each path/query param's Python type explicitly: `location_id: uuid.UUID`, `on_date: date \| None = None`. Don't rely on the path pattern alone. |
| 8 | qwen invents schema/model fields based on "reasonable" pattern-matching (`Shift.station_id`) | `AttributeError: 'Shift' object has no attribute 'station_id'` | Algorithm steps that construct a Read schema explicitly MUST list the **exact** field set with "do NOT pass any other field." Plus a Rule: Pydantic Read schemas have EXACTLY the fields declared in sprint 001's data contract. |
| 9 | In-memory SQLite test engine missing `StaticPool` + `connect_args` | Cross-session writes invisible (commit on session A, read on session B sees nothing — different in-memory DBs per connection) | Test conftest's async engine MUST be: `create_async_engine("sqlite+aiosqlite:///:memory:", echo=False, connect_args={"check_same_thread": False}, poolclass=StaticPool)` plus `from sqlalchemy.pool import StaticPool`. |
| 10 | Trailing-slash on collection routes (`@router.post("/", ...)` under prefix `/locations`) | `assert 307 == 200` (FastAPI emits 307; httpx AsyncClient doesn't follow redirects by default) | Spec rule: collection-level routes use empty-string path `""` (not `"/"`) so the route URL exactly matches the router prefix. |
| 11 | Route declaration order — parameterized path before static path | `422 Unprocessable Entity` on a static path that should match cleanly (e.g., `/shifts/browse` swallowed by `/shifts/{shift_id}`) | Within a router, declare static-path routes BEFORE parameterized routes that share their prefix. List the order explicitly in the API contract — qwen follows the structure of the spec, not its prose rules. |
| 12 | Test uses raw string UUID from `response.json()["id"]` in an ORM filter (`Registration.id == reg_id`) | `AttributeError: 'str' object has no attribute 'hex'` from SQLAlchemy's UUID bind processor in the test's own `db_session.execute(select(...))` call | Spec rule for tests: parse string ids back to UUID with `uuid.UUID(...)` before using in ORM queries. |
| 13 | Test passes Python `date`/`time`/`datetime`/`uuid.UUID` objects in an httpx `json=` body | `TypeError: Object of type date is not JSON serializable` at httpx's request build step | Spec rule for tests: serialize non-primitive values with `.isoformat()` (date/time/datetime) or `str(...)` (UUID) before passing to `json=`. |
| 14 | Test asserts on the wrong path of an error response — uses FastAPI default-HTTPException nested form (`body["detail"]["error_code"]`) when the custom `AppError` handler returns flat (`body["error_code"]`) | `TypeError: string indices must be integers, not 'str'` on the dict indexing in tests | Architect must (a) state the exception handler's exact JSON shape in Tricky Semantics, and (b) write all test assertions for error responses using the matching path. The test contract must match the handler. |

#### The meta-pattern (across all 14)

> spec leaves a gap → qwen fills it with a "reasonable-looking" choice → fails at runtime

The architect's job is to close gaps, not to write reasonable-looking sketches. A 30-token rule in the spec prevents an entire class of failure. **Each class would normally cost minutes of LocalFix iteration + paid CloudFix calls + manual debugging; closing it preemptively in the spec is dramatically cheaper.**

#### Bonus meta-rule — structural sections must match structural rules (defect 11-bis)

A prose rule in `## Rules` saying "declare static routes before parameterized" does NOT override an API contract table that lists routes in the wrong order. qwen replicates the structure of the spec, not its prose. **When you state a rule, the structural sections (tables, signatures, algorithm subsections) must embody the rule.** This is a discipline check the architect runs: are the structural sections internally consistent with the rules section?

### Two-pass review process — caught 4 ambiguities sprint 003 would have failed on

Pass 1: convert architect output to speedrun format with all 14 defect-class rules pre-applied.

Pass 2: scrutinize for ambiguities and conflicts. Specifically check:
- Where could qwen reasonably interpret two ways?
- Are there conflicts between sections (e.g., Rule says X, table says Y)?
- Do imports cover everything the algorithm references?
- Do test fixtures' dependencies match what they call?
- Does each test assertion path match the actual API response shape?
- Are there fields/values left unspecified that have unique constraints (collision risk)?
- Does the algorithm reference symbols whose values aren't pinned (e.g., "construct the second volunteer with different unique fields" — but no exact values given)?

Sprint 003 round 2 caught: (a) `req.accepted` field semantics ambiguous, (b) second volunteer values not pinned (collision risk), (c) `add_member` return shape (qwen could "improve" the response). Round 2 missed defect 14 (assertion path mismatch) — that one only surfaced at runtime. Worth tightening Round 2 to also explicitly check assertion-path-to-handler-shape correspondence.

### Pipeline mechanics fixes (in `sprint_runner_local_gen_qwen_sr.dip`)

Independent of spec quality, the dip itself had bugs we closed:

1. **RunTests routing collision**: `tests-fail-cloud` substring contained `tests-fail`, so the LocalFix edge swallowed post-exhaustion runs that should have routed to CloudFix → infinite LocalFix↔CloudFix pingpong with Layer 2 snapshot clobbering CloudFix's edits. Renamed emit token to `cloud-handoff` (no substring overlap).

2. **Strict-pass requirement**: pytest exit code 0 was insufficient — `2 passed, 8 skipped` exits 0. Added: `tests-pass` requires `passed > 0 AND failed == 0 AND errors == 0`. Skips don't count as success.

3. **Anti-mask rules in CloudFix prompt**: explicit forbidden patterns (no `try/except ImportError` shims, no `pytest.skip` markers, no commented-out code, no hand-rolled fallback classes for missing libs). Plus env-escalation channel: write to `.ai/escalation.txt` if env looks broken, don't patch around it.

4. **Lazy uv-sync in RunTests**: Setup runs before pyproject.toml exists (sprint 001 starts empty). `uv sync --all-extras` moved into RunTests as an idempotent precondition.

5. **CloudFix capability upgrade** (this session, not yet pipeline-validated):
   - `reasoning_effort: high` → `medium` (less deliberation, faster action)
   - `max_turns: 5` → `12` (headroom for multi-file edits)
   - Reads the sprint spec as input #2 (was: never saw the spec)
   - Bash includes `grep -rn` for cross-file symbol lookup (was: cat-only)
   - Drops "ONE error class, ONE edit" rule (was rigid; replaced with "fix every affected file in this session")
   - Framing: "you are debugging — find the bug, fix it, return. NOT exploring."

6. **qwen3.6:35b-a3b hyperparameters** (Generate + LocalFix in the dip):
   - `top_k: 64 → 20` everywhere (Qwen team's official recipe; default override)
   - Generate-initial: `temp=1.0, top_p=0.95, top_k=20, min_p=0, presence_penalty=1.5` — exploration with anti-repetition. The `presence_penalty=1.5` specifically prevents the "qwen writes its chain-of-thought as Python comments inside generated files" failure mode we observed without it.
   - Generate-modify / Syntax-retry / LocalFix: `temp=0.6, top_p=0.95, top_k=20, min_p=0, presence_penalty=0.0` — precision for code edits.

### What's next: bake principles into `write_sprint_docs` (Opus architect) + `write_enriched_sprint` (Sonnet writer)

Two prompt locations need updating:

1. `pipelines/spec_to_sprints.dip:537` — `agent write_sprint_docs` (Opus). Currently authors `.ai/contract.md` + iterates `write_enriched_sprint` per sprint. Needs:
   - The 14 defect classes as a pre-shipping checklist
   - The architect_v2 design pattern (front-loaded foundation + FROZEN files + auto-discovery main.py) as the default architecture
   - The speedrun spec format as the section structure (vs full-file-bodies which we'd previously gravitated to)
   - The two-pass review process as part of the architect's job

2. `tracker` repo, branch `feat/write-enriched-sprint-tool` — `write_enriched_sprint` Sonnet system prompt (out-of-tree from this repo). Needs the same 14-class checklist, plus the within-sprint subset of rules, plus structural-section consistency check.

The candidate baseline at `pipelines/docs/simmer/write-sprint-docs/result.md` already encodes "zero ambiguity" + "exact syntax" + the section structure. Update it with the 14 classes and the architect_v2 design and it becomes the new architect prompt.
