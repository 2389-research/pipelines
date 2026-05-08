# Generalizability backlog

Captured 2026-05-06 during the notebook_smoke_v8/v9/v10 validation cycle.
Audit performed by reading `sprint_runner_qwen.dip` (was
`sprint_runner_qwen.dip` at root before the consolidation;
see `../README.md` for the canonical file inventory),
`architect_only.dip`, and `principles/SCAFFOLDING-ARCHITECTURE.md`.

**Verdict:** the pipeline's *architecture* is language-agnostic — Setup,
RunTests, LocalFix, and Audit all branch on manifest files. The
*implementation underneath* has drifted Python-shaped because that's what
we've been testing. Every Python-ism found is a leaf, not a load-bearing
wall. Tier-1 + tier-2 fixes below should make the pipeline a real polyglot
runner.

Pick this up after the v10 test cycle confirms the truncation fix and the
single-session CloudFix architecture.

## Tier 1 — Mechanical surface fixes ✓ DONE (2026-05-07)

Landed via the `local_code_gen/lib/lang_profile.sh` refactor. Languages
detected by Setup and dispatched through the lib's per-language functions
(`lang_test_cmd`, `lang_src_dirs`, `lang_test_count_pattern`, etc.) so
`sprint_runner_qwen.dip` and `sprint_exec_qwen.dip` no longer have any
hardcoded language branches.

Currently first-class: **python, go, node, rust, ruby, java-maven,
java-gradle**. Each language gets:
- proj_root detection (Setup / RunTests / LocalFix all use `detect_proj_root`)
- deps install command (`lang_install_cmd`)
- test runner command (`lang_test_cmd`)
- source-dir + glob + prune patterns for context bundle (`lang_src_dirs`,
  `lang_src_glob`, `lang_src_glob_extras`, `lang_find_prune`)
- failure-block + failure-summary + failing-test-files extractors
  (`lang_failure_block`, `lang_failure_summary`, `lang_failing_test_files`)
- test-count regex for Audit (`lang_test_count_pattern` +
  `lang_test_grep_includes`)
- per-file syntax pre-check (`lang_syntax_check`)

Adding a new language now means editing **one file**: `lib/lang_profile.sh`.
No dip changes needed.

What's NOT first-class yet: .NET (csproj/sln), Elixir, Swift, etc.
Adding them is one PR-sized change to lang_profile.sh.

## Tier 2 — Prompt parametrization ✓ DONE (2026-05-07)

`Setup` writes `.ai/test_command.txt` (and `.ai/lang.txt`) based on
`lang_test_cmd` / `detect_lang` for the project. `CloudFix`'s prompt
now reads `.ai/test_command.txt` rather than hardcoding `uv run pytest`.
Per-language example shapes are listed inline in the prompt for cases
where the model wants a default before catting the file.

## Tier 3 — Architect language pack (~1 day, blocked on tier 1)

This is the deepest issue. `architect_only.dip`'s prompt and
`SCAFFOLDING-ARCHITECTURE.md` describe Patterns A and B in concretely
Python-shaped terms:

- "Pydantic schema, FastAPI/equivalent app factory" (`architect_only.dip:78`)
- "SQLAlchemy registers all classes with Base.metadata, pkgutil.iter_modules" (line 80)
- "in-memory SQLite + StaticPool, conftest dependency-override fixtures" (line 147)
- Pydantic v2 settings access patterns (line 145)
- Pytest fixture closure-binding rules (line 155)
- Scaffolding plan JSONL example uses `backend/pyproject.toml`,
  `backend/app/__init__.py`, `backend/tests/conftest.py` only (line 250-253)

The patterns themselves (front-loaded foundation vs subsystem-front-loaded)
are language-agnostic ideas. Opus learns them from these examples — given
a Rust web service spec, it'll likely try to invent `pyproject.toml`
analogs.

Fix shape: rewrite the architect prompt with **per-language scaffolding
archetypes**:

- Python (FastAPI): `pyproject.toml` + `app/__init__.py` + `conftest.py`
- Go (HTTP): `go.mod` + `cmd/server/main.go` + `internal/testutil/main.go`
- Rust (Axum): `Cargo.toml` + `src/lib.rs` + `tests/common.rs`
- Node (Express): `package.json` + `src/index.ts` + `tests/setup.ts`

Plus matching pattern-A / pattern-B prose per language. Opus picks the
relevant archetype based on the spec's language hint.

`SCAFFOLDING-ARCHITECTURE.md` should grow parallel sections per language
(or get a sibling `SCAFFOLDING-ARCHETYPES-{python,go,rust,node}.md` set)
so the pattern catalog isn't all Python.

Don't tackle tier 3 until we've actually run a non-Python smoke test —
otherwise we're guessing at what the right pattern even is for the
languages we don't already use. Pick a small Go HTTP service or Rust CLI
as the smoke test once tier 1 lands.

## Out of scope (already addressed)

- Truncation of routing markers — fixed at HEAD (`fix(runner): never tee
  verbose output to tool stdout`). Filed for tracker-level lint as
  https://github.com/2389-research/dippin-lang/issues/33.
- Manifest enforcement during LocalFix — committed as the manifest gate
  (qwen can't write to scaffolding files).
- CloudFix architecture — single-session iterative loop with internal
  pytest, validated in v8/v9.
