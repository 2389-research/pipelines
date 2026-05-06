# Generalizability backlog

Captured 2026-05-06 during the notebook_smoke_v8/v9/v10 validation cycle.
Audit performed by reading `sprint_runner_qwen.dip` (was
`sprint_runner_local_gen_qwen.dip` at root before the consolidation;
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

## Tier 1 — Mechanical surface fixes (~2 hrs)

Add detection branches for languages we already partly support.

| Where (file:line) | Currently | Add |
|---|---|---|
| `sprint_runner_local_gen_qwen.dip:72-78` (Setup) | uv / npm / go | cargo, bundle, mvn/gradle, dotnet |
| `sprint_runner_local_gen_qwen.dip:239-250` (RunTests) | go test, npm test, uv run pytest | cargo test, bundle exec rspec, mvn test, dotnet test |
| `sprint_runner_local_gen_qwen.dip:341-349` (LocalFix FILE_LIST) | `.go` / `.ts`+`.js` / `.py` | `.rs`, `.rb`, `.java`, `.cs`, `.ex` |
| `sprint_runner_local_gen_qwen.dip:496-507` (Audit test count) | `^func Test`, `describe\|it\|test\(`, `^def test_` | Rust `#[test]`, Ruby `def test_` (RSpec), Java `@Test` |
| `sprint_runner_local_gen_qwen.dip:143` (LocalFix syntax check) | `gofmt`, `py_compile`, `node --check` (deprecated) | replace `node --check` with `node -c`; consider `cargo check` for Rust |

Also broaden the existing Node test-count regex (line 502-503) — it only
matches Mocha/Jest. Vitest, Cypress, and async patterns slip through.

## Tier 2 — Prompt parametrization (~1 hr)

`CloudFix` prompt at `sprint_runner_local_gen_qwen.dip:554-555` literally
hardcodes:

```
cd backend && uv run pytest -x --tb=short
```

We're telling the model to run pytest. Fix:

1. `Setup` writes `.ai/test_command.txt` based on detected language.
   Examples:
   - Python: `cd backend && uv run pytest -x --tb=short 2>&1 | tail -80`
   - Go: `cd backend && go test ./... 2>&1 | tail -80`
   - Rust: `cargo test --lib 2>&1 | tail -80`
2. `CloudFix` prompt reads `.ai/test_command.txt` and invokes whatever's
   there.

`LocalFix` is already cleaner — picker prompt is language-agnostic; only
its FILE_LIST construction is language-specific (covered in tier 1).

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
