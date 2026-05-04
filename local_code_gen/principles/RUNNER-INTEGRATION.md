# Runner integration: v4 specs → qwen sprint runner end-to-end

How the architect-side outputs (post-[STRUCTURAL-FIX-RESULTS.md](STRUCTURAL-FIX-RESULTS.md)) flow through the local-gen runner and produce a working FastAPI app. Validates the full chain: spec_analysis.md → contract.md → SPRINT-NNN.md → backend code → passing tests.

**End-to-end result on the Notebook synthetic (2026-05-01):** 34/34 pytest passing. Spec → working code in 17 min, ~$0.30 of cloud spend (architect already paid separately).

## The two pipelines and what bridges them

```
┌──────────────────── Architect side (cloud) ────────────────────┐
│                                                                  │
│  inputs/spec.md  →  spec_analysis  →  sprint_plan                │
│                                                                  │
│  Opus designs:                                                   │
│    .ai/contract.md            (cross-sprint architectural map)   │
│    .ai/sprint_descriptions.jsonl  (one line per sprint)          │
│                                                                  │
│  Sonnet expands (one author + audit pass per sprint):            │
│    .ai/sprints/SPRINT-001.md  (foundation, ~30KB)                │
│    .ai/sprints/SPRINT-002.md  (additive, ~14KB)                  │
│    .ai/sprints/SPRINT-003.md  (additive, ~17KB)                  │
│                                                                  │
│  .ai/ledger.tsv populated with all sprints `planned`             │
│                                                                  │
│  Pipeline: local_code_gen/architect_only.dip                     │
│  Cost: ~$2 / 9 min                                               │
│                                                                  │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             │  bridge: .ai/sprints/SPRINT-NNN.md
                             │          .ai/ledger.tsv
                             │          .ai/contract.md (read-only by runner)
                             ▼
┌──────────────────── Runner side (local + cloud-on-handoff) ─────┐
│                                                                  │
│  For each sprint in ledger:                                      │
│    Generate (qwen):    parse `## New files`, gen_file each      │
│    RunTests:           uv run pytest                            │
│    LocalFix (qwen):    SR-block surgical edits                  │
│      ↳ retry up to 10 LocalFix rounds                           │
│    CloudFix (gpt-5.4): cloud agent if local exhausts            │
│    Audit:              artifact + test-count gates              │
│    Commit:             git commit per sprint                    │
│                                                                  │
│  Pipeline: local_code_gen/sprint_runner.dip                      │
│  Cost (this run): ~$0.30 cloud + $0 local                        │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## What broke when we first plugged v4 specs into the runner

Three section-name mismatches between the architect's new (speedrun-aligned) output and the runner's existing (v1-shape) consumer:

| Where | Runner expected | v4 architect emits |
|---|---|---|
| `Generate` user-prompt hint to qwen | "Use the Interface contract, Algorithm notes, Imports per file, Test plan sections" | `## Data contract`, `## Algorithm`, `## Test contract` (no separate Imports per file) |
| `Audit` artifact-presence check | scans `## Expected Artifacts` for paths | section doesn't exist in v4 |
| `Audit` test-count check (Python branch) | counts `^def test_` inside `## Test plan` | uses `## Test contract` with backticked test names in tables |

Net effect on a v4 spec running through the SR runner *before* the fix:
- **Generate** still works (its file-discovery uses `## New files` + `## Modified files` — both present in v4); the user-prompt hint is informational, qwen finds the actual content.
- **Audit's artifact-presence check silently does nothing** on v4 specs — the awk loop never enters the in-section branch.
- **Audit's test-count check returns 0 for sprint_tests** — counts `def test_` in a section that doesn't exist; passes the "actual >= sprint" gate vacuously.

## Fix: section-name alignment in `local_code_gen/sprint_runner.dip`

Three small edits to the runner dip:

1. **Audit artifact-presence check** — replace the single `## Expected Artifacts` scan with a function `check_artifact_section` called for each of `## New files`, `## Modified files`, and (legacy fallback) `## Expected Artifacts`. Every artifact in any of the three sections gets file-existence checked.

2. **Audit test-count check** — change awk pattern from `/^## Test plan/` to `/^## (Test contract|Test plan)/`. For Python, count backticked test names from per-file tables (v4 format: `` `test_foo(client, ...)` ``); fall back to `^def test_` line count for v1-format specs. Actual-tests count uses `^(async )?def test_` to also match async test functions (v4 style).

3. **Generate gen_file/patch_file user-prompt hint** — point qwen at "Data contract (types/schemas), API contract (route table), Algorithm (per-route prose), Test contract (per-file tables), and Verbatim files (tiny configs)" instead of the v1 section names. Keep v1 names as a documented fallback so older specs still work.

The dip validates clean post-fix (`tracker validate local_code_gen/sprint_runner.dip` → 19 pre-existing harmless warnings, 0 errors).

## Fix: 4-strategy SR-block matcher in the auditor

The architect-side audit pass (Sonnet patches drafts via SR blocks) and the runner-side LocalFix (qwen patches failing source via SR blocks) use the same Aider-style format. The runner has a robust Python merger at `pipelines/lib/merge_sr.py` with 4 fallback strategies; the auditor in `tracker/agent/tools/write_enriched_sprint.go` was using exact-match-only with a `count == 1` uniqueness check, which fell back to the unaudited draft on any whitespace drift.

**Ported the 4 strategies into Go** (`applySRBlocks`):

| Strategy | When it fires | Behavior |
|---|---|---|
| `exact` | SEARCH appears verbatim in the draft | `strings.Replace(draft, search, replace, 1)` |
| `indent` | SEARCH has uniform leading indent (e.g., `"    x = 1\n    y = 2"`); chunk in draft has uniform leading indent too | dedent SEARCH by its uniform indent, find dedented match in dedented chunk, then re-indent REPLACE by chunk's indent (handles the case where the LLM emitted SR at one indent level and the draft has the same content at a different one) |
| `whitespace` | line-count-matching window in draft has the same collapsed-whitespace form as SEARCH | replace chunk verbatim with REPLACE (catches whitespace drift within lines — extra spaces, tab-vs-space) |
| `fuzzy` | Levenshtein-distance ratio ≥ 0.9 between best-scoring N-line window and SEARCH | replace best-scoring chunk with REPLACE (catches minor character drift the earlier strategies miss) |

Strategies are tried in this order; first match wins. **Indent precedes whitespace** so that uniform-indent SEARCH correctly re-indents its REPLACE rather than the whitespace strategy clobbering with verbatim REPLACE.

Implementation lives in `tracker/agent/tools/write_enriched_sprint.go` alongside the existing `parseAuditResponse` / `parseSRBlocks` helpers. 12 unit tests in `write_enriched_sprint_test.go` cover the four strategies, the strategy-ordering invariant, multi-block ordering, empty-SEARCH rejection, and `similarityRatio` known-pair values.

The Levenshtein-distance implementation uses a rolling two-row DP, O(la × lb) time, O(min(la, lb)) space. Approximates Python's `difflib.SequenceMatcher.ratio()` closely at threshold 0.9 — both metrics agree on whether two strings are "approximately equal" for our use case (auditor catching minor character drift in audit SR blocks).

## End-to-end run on Notebook fixtures (2026-05-01 11:12)

Workdir: `experiments/notebook_smoke_v4/`. Architect already produced specs (3-sprint Notebook API). Runner executed `local_code_gen/sprint_runner.dip` cold on those specs.

### Per-sprint timeline

| Sprint | Files generated | Generate time | LocalFix rounds | CloudFix rounds | Audit | Commit |
|---|---|---|---|---|---|---|
| 001 (foundation) | 18 (incl. 3 empty `__init__.py`) | 2m46s | **11** | **2** | pass | a381425 |
| 002 (notes CRUD) | 2 | 1m09s | 0 | 0 | pass | 39c51b0 |
| 003 (tags + filter) | 4 | 1m04s | 0 | 0 | pass | 78870be |

**Total: 17m03s wall, 13 LLM turns, 16 cloud tool calls, 147,673 input / 4,854 output tokens (gpt-5.4).**

### Final test state

```
$ cd backend && uv run pytest -v --tb=no
============================== 34 passed in 7.35s ==============================
```

Coverage:
- `test_health.py` — 1 test
- `test_models.py` — 4 tests (User/Note/Tag fields + many-to-many relationship)
- `test_auth.py` — 5 tests (signup ×2, login ×3)
- `test_config.py` — 1 test
- `test_notes.py` — 11 tests (CRUD + cross-user isolation)
- `test_notes_by_tag.py` — 4 tests (filter + isolation)
- `test_tags.py` — 7 tests (CRUD + cross-user isolation + cascade-unlink)

### What the asymmetry tells us

**Sprint 001 (foundation)** needed 11 LocalFix + 2 CloudFix to converge. **Sprint 002 and Sprint 003 (additive)** ran clean: Generate → RunTests → Audit → Commit, no fixes needed.

This is **the speedrun spec validation we wanted at the runner level.** When the foundation sprint has the contract right (data model, conventions, test fixtures, error shape), and additive sprints inherit cleanly with full Tricky semantics + Algorithm prose + per-test-file Test contract, qwen produces working code on the first pass for additive sprints. No oscillation, no cloud handoff, no manual cleanup.

The asymmetry also reveals the dominant **dependency-error vs logic-error defect class split.**

## Defect class observation: dependencies aren't logic

Sprint 001's 11 LocalFix rounds didn't oscillate over code logic — they oscillated because **`pyproject.toml` was missing `email-validator`**. Pydantic's `EmailStr` (used by `UserCreate`) requires that package. The first import-time failure looks like a Pydantic validation error, but the fix isn't in the code — it's a missing dependency.

Local qwen kept patching `auth.py`, `conftest.py`, etc., trying to make the symptoms go away. Each patch made the test slightly different but never resolved the root cause. After 11 rounds the local-attempts budget exhausted and `local_exhausted` was written. CloudFix took one look and added `email-validator>=2.0.0` to dependencies — done in 30 seconds.

This is a recurring pattern. Two adjacent defect classes:

| Class | Symptom shape | Best fix path |
|---|---|---|
| **Logic / contract violation** | Test asserts behavior X; code does Y. AttributeError from a missing field. AssertionError on response shape. | Local qwen + SR blocks — these are pattern-based fixes the local model is good at. |
| **Dependency / config / version** | `ImportError`, `ModuleNotFoundError`, `RuntimeError: <ext> requires <pkg>`, `ValueError: password cannot be longer than 72 bytes` (from passlib + bcrypt 5.x compat), build errors before tests even run. | Cloud agent (or human) — needs to read pyproject.toml, know which extras are required for which features, possibly version-pin to dodge upstream incompatibilities. |

**Proposed early-escalation heuristic** for the runner (not yet built):

```
After each RunTests, classify the failure:
  if test output contains: ImportError|ModuleNotFoundError|requires the .* package
                          |"<extra>" extra is required
                          |"X" object has no attribute "__about__"   (passlib+bcrypt)
                          |TypeError: object of type X is not callable
  → escalate immediately to CloudFix (skip LocalFix loop)
```

A regex check on `last_test_output.txt` would skip the 5 minutes of LocalFix oscillation we saw on sprint 001. Not a runner-design change, just a routing heuristic. Worth landing before NIFB acceptance.

## Cost analysis: this run vs all-cloud equivalent

Token counts on the generated `backend/` (excluding `.venv`, `__pycache__`):

```
26 files, 1,144 lines, 36,971 chars, 8,750 tokens (cl100k tokenizer)
```

**What we actually paid:**

| Stage | Provider | Tokens (in / out) | Cost |
|---|---|---|---|
| Architect (Opus design + 3× Sonnet author + 3× Sonnet audit) | Anthropic | ~90K total | ~$2 |
| Runner Generate (26 file-gens) | qwen3.6 local | — | $0 |
| Runner LocalFix (11 rounds, sprint 001) | qwen3.6 local | — | $0 |
| Runner CloudFix (2 rounds, sprint 001) | OpenAI gpt-5.4 | 147,673 / 4,854 | ~$0.30 |
| **Total** | | | **~$2.30** |

**What an all-cloud equivalent would cost** (gpt-5.4 doing every step):

| Stage | Estimated tokens | Estimated cost |
|---|---|---|
| Generate (26 files × ~9K context+output) | ~235K | ~$1.50 |
| LocalFix (11 rounds × ~12K each) | ~130K | ~$0.65 |
| CloudFix (already cloud, ~$0.30 actual) | actual | ~$0.30 |
| Architect (already cloud, ~$2 actual) | actual | ~$2 |
| **Total all-cloud** | | **~$4.45** |

**Idealized one-shot generation (no agent loop, no test feedback)** — what the FLOOR cost would be if a frontier model wrote it perfectly first try:

```
Output: 8,750 tokens
Input:  ~30K context per call × 26 calls ≈ 780K (or one big call: ~50K context + 8.75K output)
Cost:   ~$0.40 (one-shot) / ~$1-2 (per-file calls without feedback loop)
```

This is the floor — assumes the model never needs to fix mistakes. Even a frontier model would likely miss the same dep-pinning issues we hit, so realistic cost is closer to the agentic estimate above.

**Cost ratio (local-first vs all-cloud): ~2× cheaper.** Higher savings on bigger projects where Generate dominates (NIFB-scale 16-sprint runs would be ~10× the file count, ~5× the LocalFix budget — same architect cost; runner side scales linearly).

For asynchronous runs (kick off, come back later), the local-first model is the right economics. Wall-time cost of using qwen vs gpt-5.4 is ~17 min vs ~8-10 min — fine for kickoff-and-walk-away workflows.

## What this validates and what's still open

**Validated end-to-end on synthetic (Notebook API):**
- Architect-side speedrun specs (post-prompt-rewrite) drive qwen to produce working code that passes 34/34 tests.
- Sprint 002 + 003 (additive) generate cleanly first try — no LocalFix needed when foundation is correct.
- TerminalTool stops the architect cleanly; SR-block 4-strategy matcher reduces audit fallback rate.
- Cost is ~$2.30 end-to-end for a 1144-LoC FastAPI app from a 30-line spec.

**Still open:**
- **NIFB acceptance test** — re-run on production-scale spec (16 sprints). Not yet attempted post-fix.
- **Early-escalation for dep errors** — eliminate the ~5 min sprint-001 LocalFix oscillation with a regex check on `ImportError`/`ModuleNotFoundError`/`<extra>` keywords. Not yet built.
- **Runner-side audit gate strictness** — current Audit only checks file existence and test-count parity. Doesn't verify pytest-pass (RunTests handles that earlier). Worth confirming the gate sequencing on edge cases (e.g., passing audit but failing pytest at end).
- **`merge_sr.py` Go port test coverage** — covered the strategy-ordering invariants and known similarity-ratio pairs; could add a test that explicitly fuzzes SEARCH text from a known draft to confirm the strategies don't match wrong chunks (false positives).

## Files modified in this round

| File | Change |
|---|---|
| `tracker/agent/tools/registry.go` | Added `TerminalTool` interface + `IsToolTerminal` helper |
| `tracker/agent/session_run.go` | `executeToolCalls` now returns `terminate bool` reflecting whether any executed tool succeeded as a TerminalTool |
| `tracker/agent/session.go` | Loop now breaks when `terminate == true` after `executeToolCalls` |
| `tracker/agent/tools/dispatch_sprints.go` | `IsTerminal() bool { return true }` + `runOneWithRetry` with bounded backoff for retryable provider errors |
| `tracker/agent/tools/write_enriched_sprint.go` | Replaced exact-match-only `applySRBlocks` with 4-strategy matcher (exact / indent / whitespace / fuzzy); added supporting helpers (`commonLeadingIndent`, `dedentLines`, `indentLines`, `similarityRatio`, `levenshteinDistance`, `splitKeepNewlines`, `collapseWhitespace`) |
| `tracker/agent/tools/write_enriched_sprint_test.go` | 12 unit tests covering all four match strategies + similarity ratio + parser |
| `pipelines/local_code_gen/sprint_runner.dip` | Audit gate scans `## New files` + `## Modified files` (with legacy fallback); test-count uses `## Test contract` (with v1 fallback); Generate prompt hint mentions both v4 and v1 section names |
| `local_code_gen/architect_only.dip` | Replaced `agent Start` and `agent Exit` with `tool` nodes (zero-LLM markers) |
| `local_code_gen/principles/synthetic_fixtures/notebook_*.md` | Notebook API synthetic fixtures (spec_analysis + sprint_plan, ~150 lines combined) |
| `local_code_gen/principles/STRUCTURAL-FIX-RESULTS.md` | Updated to track v1→v4 progression |
| `local_code_gen/principles/RUNNER-INTEGRATION.md` | (this doc) — runner-side integration outcomes + cost analysis |
