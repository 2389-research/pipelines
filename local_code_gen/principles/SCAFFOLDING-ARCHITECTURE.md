# Scaffolding-first architecture (Phase 2)

**Status:** Validated end-to-end against `experiments/notebook_smoke_v4` on 2026-05-05.
**Goal:** Eliminate verbatim-transcription failures in qwen by routing all bytes-pinned files through a deterministic pre-pass before per-sprint codegen runs.

## Problem this solves

Earlier runs of the local code-gen flow exhibited a recurring failure class: qwen would faithfully transcribe **most** of a contract-pinned file (e.g. `pyproject.toml`) but silently drop or invent specific lines:

- `asyncio_mode = "auto"` omitted from `[tool.pytest.ini_options]` → all async tests skipped
- `addopts = "tests"` invented (not in spec) → `--all-extras` install behavior changed
- `python_files = ["test*.py"]` invented → matches stricter than the contract intends
- `from sqlalchemy import StaticPool` mis-imported as `from sqlalchemy.pool import StaticPool` → wrong driver
- Custom indentation, dropped trailing newlines on TOML alignment-sensitive blocks

Research literature [arxiv 2601.03640] confirms this is a quantized/local-model failure mode at scale: *"none of the evaluated models achieve a perfect transcription at 300+ items."* qwen3.6:35b at q8 is a transcriber, not a designer — but boilerplate transcription *itself* fails at scale.

## Architecture: 3-tier model split

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│  Architect (Opus 4.6)         — cross-sprint reasoning, ALL decisions       │
│  $15/$75 per Mtok                                                            │
│  Once per project. Writes:                                                   │
│    • .ai/contract.md             (architectural decisions, byte-pinned bytes)│
│    • .ai/sprint_descriptions.jsonl  (one record per sprint)                  │
│    • .ai/scaffolding_plan.jsonl     (one record per scaffolding file)        │
│  Then dispatches to two tools.                                               │
└──────────────────────────────────────────────────────────────────────────────┘
                                  │
                ┌─────────────────┴───────────────────┐
                ▼                                     ▼
┌────────────────────────────────┐   ┌────────────────────────────────────────┐
│  dispatch_scaffolding          │   │  dispatch_sprints                      │
│  loops scaffolding_plan.jsonl  │   │  loops sprint_descriptions.jsonl       │
│                                │   │                                        │
│  per-entry → write_scaffolding │   │  per-entry → write_enriched_sprint     │
│              _file (Haiku 4.5) │   │              (Sonnet 4.6)              │
│  $0.80/$4 per Mtok              │   │  $3/$15 per Mtok                       │
│                                │   │                                        │
│  job: transcribe ONE file from │   │  job: expand per-sprint description    │
│  contract anchor → JSON.       │   │  into full enriched sprint markdown.   │
│  required_lines validated      │   │  Reads scaffolding manifest; emits     │
│  before write — drift fails    │   │  `## Files already on disk` section to │
│  the per-file pass, not the    │   │  prevent qwen from regenerating files  │
│  whole batch.                  │   │  already pinned by Haiku.              │
│                                │   │                                        │
│  writes:                       │   │  writes:                               │
│    • <project>/<file> × N      │   │    • .ai/sprints/SPRINT-NNN.md × N     │
│    • .ai/scaffolding_manifest  │   │                                        │
└────────────────────────────────┘   └────────────────────────────────────────┘
                │                                     │
                └─────────────────┬───────────────────┘
                                  ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  qwen3.6:35b (Ollama, local, ~free)                                          │
│  Per-sprint exec — generates ALGORITHMIC files only                          │
│  Reads SPRINT-NNN.md; sees `## Files already on disk` (skips), `## New files`│
│  (writes), `## Modified files` (patches).                                    │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Key design principles

### 1. All decisions at the architect level

The act of being in `scaffolding_plan.jsonl` IS the scaffolding decision. Workers never decide "is this file scaffolding?" at runtime. This eliminates the prior tagging contradiction where Opus marked `conftest.py` as "algorithmic — Sprint 001 writes, FROZEN" while *also* pinning its full bytes verbatim — Haiku read the explicit "algorithmic" tag and skipped the file, leaving qwen to drift on a 60-line transcription job.

The new dimension is **bytes-pinned vs behavior-described**, not config-vs-application-code. If the contract has a fenced verbatim block for a file, it goes in the JSONL regardless of whether it lives in `tests/`, `app/`, or `cmd/`.

### 2. Right-sized model per layer

- **Opus** for architect-level work: cross-sprint reasoning, picking architectural patterns (front-loaded vs subsystem-decomposed), authoring the contract, deciding the sprint plan. Expensive per token but small token budget — runs once per project.
- **Sonnet** for per-sprint enrichment: expands sprint descriptions into full enriched markdown with cross-file consistency. Reads contract on every call. ~3 calls × ~6k output for typical projects.
- **Haiku** for scaffolding transcription: pure structured-output JSON envelope (one file's bytes from one contract anchor). Narrow scope per call → small input/output → ~3-4× cheaper than Sonnet for this workload.
- **qwen** (local) for algorithmic codegen: writes route handlers, business logic, test bodies from per-sprint specs. Free per token but needs narrow inputs.

### 3. Per-file isolation and validation

`write_scaffolding_file` validates `required_lines` (architect-pinned distinctive substrings) BEFORE writing each file. If Haiku drifts on `asyncio_mode = "auto"`, the per-file call fails with a clear error and the file is not written. The dispatch loop continues with other files (in non-strict mode) or halts (strict mode). qwen never sees a file with silent corruption.

Per-file retry on transient errors mirrors `dispatch_sprints`'s retry pattern.

### 4. Manifest as runtime contract between layers

`.ai/scaffolding_manifest.txt` is the bridge between `dispatch_scaffolding` (writer) and `dispatch_sprints` → `write_enriched_sprint` (reader):

```text
backend/pyproject.toml
backend/app/__init__.py
backend/app/main.py
backend/tests/conftest.py
...
```

Per-sprint Sonnet reads the manifest and:
- Emits a `## Files already on disk` section listing those paths (paths only, no contents)
- Excludes those paths from `## New files` and `## Verbatim files`
- May still reference them in algorithm prose, imports, and rules (read-only references)

The qwen exec layer extracts paths only from `## New files` / `## Modified files`. Scaffolding files in `## Files already on disk` are naturally skipped — no runner change needed.

## File contracts

### `.ai/scaffolding_plan.jsonl` (architect → dispatch_scaffolding)

One JSON object per line:

```jsonl
{"path": "backend/pyproject.toml", "description": "Verbatim from contract Appendix A.11 — pyproject.toml with hatchling build, all deps including email-validator>=2.0, wheel packages=[app], pytest asyncio_mode=auto.", "required_lines": ["asyncio_mode = \"auto\"", "email-validator>=2.0", "packages = [\"app\"]"]}
{"path": "backend/tests/conftest.py", "description": "FROZEN — full test fixture set verbatim from contract Appendix A.12.", "required_lines": ["from sqlalchemy import StaticPool", "expire_on_commit=False", "_override_get_db", "second_auth_headers"]}
```

Required: `path` (workspace-relative), `description` (anchor pointer for Haiku).
Optional but strongly recommended: `required_lines` (distinctive substrings — load-bearing identifiers Haiku's transcription must satisfy).

### `.ai/sprint_descriptions.jsonl` (architect → dispatch_sprints)

Unchanged from prior architecture — one record per sprint with `path` (e.g. `SPRINT-001.md`) and `description` (per-sprint slice of the contract).

### `.ai/scaffolding_manifest.txt` (dispatch_scaffolding → dispatch_sprints)

One workspace-relative path per line. Written after every successful per-file scaffolding pass; lists only paths actually written (failures are excluded from the manifest but logged in the dispatch summary).

## Per-sprint output shape

Every `SPRINT-NNN.md` under the new architecture contains:

```markdown
# Sprint NNN — Title (enriched spec)

## Scope
## Non-goals
## Dependencies
## Conventions
## Tricky semantics
## Data contract
## API contract
## Algorithm
## Test contract
## Files already on disk      ← NEW: lists scaffolding paths qwen must skip
## New files                  ← algorithmic files only — qwen generates these
## Modified files
## Rules
## DoD
## Validation
```

The `## Verbatim files` and `## Trivial file contents` sections are typically empty or omitted under the new architecture (their previous content lives in the scaffolding manifest).

## Failure modes prevented

| Class | How prevented |
|---|---|
| `asyncio_mode` line dropped from pyproject.toml | `required_lines` enforced per-file before write |
| Wrong `StaticPool` import path in conftest.py | `required_lines` includes exact import line |
| qwen overwriting FROZEN files on later sprints | Files listed in `## Files already on disk`, excluded from `## New files`; runner extracts paths only from `## New files` / `## Modified files` |
| `conftest.py`-class trap (algorithmic-tagged but bytes-pinned) | Architect's tag dimension changed from "config-vs-test" to "bytes-pinned-vs-behavior-described" — explicit JSONL listing routes the file through scaffolding regardless of category |
| Path doubling (`backend/backend/pyproject.toml`) | Workspace-relative paths throughout; no proj_root prepending in the writer |
| `tool_use.input: Field required` (Anthropic API) | tracker `llm/anthropic/translate.go` emits `input: {}` for tool_use with empty args |

## Cost framing (notebook_smoke_v4 — small project, validation-grade)

| Stage | Model | Cost |
|---|---|---|
| Architect (Opus) | claude-opus-4-6 | ~$0.40 |
| Scaffolding (14 files × Haiku) | claude-haiku-4-5 | ~$0.03 |
| Sprint enrichment (3 sprints × Sonnet) | claude-sonnet-4-6 | ~$0.30 |
| **Total** | | **~$0.43** |

Compared to prior architecture (Sonnet for everything): ~$0.48. The savings is small for a 14-file project; scales with project size. NIFB-class projects (40+ scaffolding files, 16 sprints) would see proportionally larger gains.

The qwen exec layer remains essentially free (local Ollama + occasional CloudFix gpt-5.4 fallback).

## Runtime tools (tracker)

| Tool | Purpose | Default model |
|---|---|---|
| `write_scaffolding_file` (singular) | One file per call. Internal — agent should NOT call directly. | claude-haiku-4-5 |
| `dispatch_scaffolding` | Loops scaffolding_plan.jsonl, calls write_scaffolding_file per entry, emits manifest. | n/a (orchestrator) |
| `write_enriched_sprint` | One sprint per call. Internal. Reads manifest if dispatch_sprints provides it. | claude-sonnet-4-6 |
| `dispatch_sprints` | Loops sprint_descriptions.jsonl, threads manifest into each per-sprint call. | n/a (orchestrator) |

Env vars:
- `TRACKER_SPRINT_WRITER_MODEL` / `TRACKER_SPRINT_WRITER_PROVIDER` — required; gates `dispatch_sprints` + `write_enriched_sprint`
- `TRACKER_SCAFFOLDING_WRITER_MODEL` / `TRACKER_SCAFFOLDING_WRITER_PROVIDER` — optional; falls back to sprint writer model. Default Haiku-tier when set independently.

## Open questions / Phase 3+ ideas

1. **Deterministic transcription as alternative to Haiku.** If the architect contract has a stable structure (one fenced code block per `### \`<path>\`` heading), a parser could extract verbatim bytes without any LLM call — eliminating drift entirely at zero cost. Would require the architect prompt to enforce stable structure, which Opus may resist on contract pages with prose explanations between blocks. Worth prototyping for projects where every byte must be defensible.

2. **Cross-architecture contract reuse.** `scaffolding_plan.jsonl` is project-specific today. Common scaffolding (FastAPI + SQLAlchemy + pytest-asyncio + httpx) repeats across projects. A shared "stack pack" of pre-validated scaffolding blocks (with required_lines pinned) would let the architect reference rather than re-author.

3. **Validate scaffolding via `uv sync --all-extras` post-write.** The runner's Setup step does this implicitly during sprint exec. Promoting it to a `validate_scaffolding` tool that runs immediately after `dispatch_scaffolding` would surface dependency-resolution failures (e.g., a pinned version that doesn't exist on PyPI) at architect time rather than first-sprint time.

## Lineage

Earlier iterations of this architecture lived in `experiments/notebook_smoke_v4`. The convergence to the current shape happened across several end-to-end runs on 2026-05-05:

1. **Initial state**: qwen wrote everything per-sprint; verbatim-drift failures common.
2. **First scaffolding tool** (plural `write_scaffolding_files`): single Sonnet call decided + transcribed all scaffolding. Discovered the path-doubling bug and the architect-side tagging contradiction.
3. **Per-file dispatch pattern** (current): architect explicitly lists scaffolding files; per-file Haiku transcription with required_lines validation. Conftest.py correctly classified.
4. **Phase 2 — manifest threading**: per-sprint Sonnet sees the manifest and emits `## Files already on disk`. Sprint specs shrink ~30% on foundation sprints. qwen task list is now narrow and algorithmic-only.
