# Local-gen pipeline — methodology and results

> Covers `sprint_exec_local_gen_qwen.dip` and `sprint_exec_local_gen_gemma.dip`.

## What it does

Executes an enriched sprint spec using a **local Ollama model for both generation and fixing**, with a cloud model (gpt-5.4) as a last-resort fallback. Happy path costs $0.00. Cloud is only consumed when the local model exhausts 4 fix attempts.

```
Setup          detect language, install deps (go mod tidy / npm install / uv sync)
Generate       one Ollama call per file; patch_file() for modified files, gen_file() for new
  └ validate   after each write: gofmt -e / py_compile / node --check → retry up to 2× at temp 0.1
RunTests       go test ./... / npm test / uv run pytest → tests-pass / tests-fail / tests-fail-cloud
LocalFix       two Ollama calls: "which file?" → "rewrite it"; up to 4 attempts
  └ validate   same syntax gate after writing the fix
CloudFix       gpt-5.4 agent, one targeted fix per session, max 6 retries
Audit          shell check: all Expected Artifacts exist, test count ≥ sprint spec count
Done
```

## Language detection

The pipeline auto-detects from indicator files. No configuration needed.

| Indicator | Test runner | File glob (LocalFix) | Syntax check | Test pattern (Audit) |
|-----------|-------------|----------------------|--------------|----------------------|
| `go.mod` | `go test ./...` | `find . -name "*.go"` | `gofmt -e 2>&1 >/dev/null` | `^func Test` |
| `package.json` | `npm test` | `find . -name "*.ts" -o -name "*.js"` | `node --check` | `(describe\|it\|test)(` |
| `pyproject.toml` / `requirements.txt` | `uv run pytest` | `find . -name "*.py"` | `python3 -m py_compile` | `^def test_` |

## Sprint spec format

The pipeline reads from `.ai/sprints/SPRINT-*.md`. Three section formats are supported:

**New files + Modified files (recommended for sprints that patch existing code):**
```markdown
## New files
- `internal/config/config.go`
- `internal/config/loader.go`

## Modified files
- `cmd/agent/main.go` — add three switch cases (tui, serve, run); see code blocks above
```
`gen_file()` is called for new files (skips if already exists). `patch_file()` reads the existing file, sends it with the sprint spec, and asks the model to apply only the described changes.

**Legacy format (backward compatible):**
```markdown
## Expected Artifacts
- `src/routes/health.ts`
- `db/migrations/001_init.sql`
```
Falls back to `gen_file()` for all listed paths.

## Validate-and-retry

After every file write (in both Generate and LocalFix), the pipeline runs a fast local syntax check. If the check fails, it feeds the error plus surrounding line context back to the local model and retries at `temperature: 0.1` (deterministic self-correction). Max 2 retries before passing through to the test loop.

**Critical implementation note for Go:**
`gofmt -e` writes the formatted file to stdout even for valid files. Use `gofmt -e 2>&1 >/dev/null` to capture only stderr (actual errors). The naive `2>&1` form makes every valid Go file appear broken, triggering retries on all files and adding minutes to Generate.

**What it catches:** literal newlines in Go string literals, unterminated strings, Python `SyntaxError`, JS/TS parse errors.

**What it doesn't catch:** semantic type errors, wrong signatures that compile, logic bugs. These are caught by the test loop.

## LocalFix design

Two Ollama calls per attempt:
1. **"Which file?"** — given test output + all source file paths + sprint spec → returns one relative path
2. **"Rewrite it"** — given the identified file + test output + sprint spec → returns corrected file content

The two-call approach is necessary because test tracebacks point to the test file (where the assertion fails), not the implementation file (where the bug lives). The first call reasons about which source file is responsible.

Full file rewrite (not diff/patch) is used for both calls. Small models are unreliable at structured edit formats. Consistent with Aider's recommendation for weaker models.

`.ai/local_exhausted` flag prevents re-entry: once LocalFix sets it, RunTests outputs `tests-fail-cloud` instead of `tests-fail`, routing directly to CloudFix for all subsequent test failures.

## Results

Validated on 4 sequential cumulative Go sprints (code_agent project, enriched sprint format).

| Sprint | Duration | Path | Cost |
|--------|----------|------|------|
| 001 | 1m00s | Fully local, 0 fixes | $0.00 |
| 002 | 23.9s | Fully local, 0 fixes | $0.00 |
| 003 | 3m02s | Fully local, 0 fixes | $0.00 |
| 004 | 3m14s | 4 local fixes + 1 CloudFix | ~$0.02 |
| **Total** | **~7m40s** | | **~$0.02** |

Sprint 004 hit the recurring **newline-in-string bug**: `patch_file()` on `cmd/agent/main.go` — qwen emitted a literal newline instead of `\n` inside a double-quoted Go string. 4 LocalFix attempts couldn't resolve it (qwen's self-correction sometimes traded the syntax error for a semantic one); CloudFix fixed it in one session.

Deliberately injecting the same bug into the sprint 3 codebase before running sprint 4 produced an identical result — the pipeline handles pre-broken code the same way as organically broken code.

## Prerequisites

- Ollama running locally at `http://localhost:11434`
- Model pulled: `ollama pull qwen3.6:35b-a3b-q8_0` or `ollama pull gemma4:26b`
- `jq` on PATH (used for JSON construction in bash nodes)
- `OPENAI_API_KEY` set (only consumed when local model exhausts)

## Running

```bash
# Place enriched sprint spec at:
mkdir -p .ai/sprints
cp SPRINT-001_enriched.md .ai/sprints/

tracker -w /path/to/project sprint_exec_local_gen_qwen.dip
```

## Model comparison

| Model | Avg gen time | Cloud needed | Notes |
|-------|-------------|--------------|-------|
| qwen3.6:35b-a3b-q8_0 | ~21s/file | 0/2 runs (NIFB Sprint 1) | Slower, cleaner output |
| gemma4:26b | ~10s/file | 1/2 runs (NIFB Sprint 1) | Faster, noisier output |

Too few runs to be conclusive — the bimodal pattern (fully local or cloud-needed) persists for both.

## Known limitations

- The newline-in-string bug in `patch_file()` on Go files is a persistent failure mode. Validate-and-retry catches many instances but qwen can swap the syntax error for a semantic one. The bug reliably lands in CloudFix territory.
- Language detection falls through to a broad `find . -type f` for unknown project types — not useful. Add `elif` branches for Rust (`Cargo.toml`), Ruby (`Gemfile`), Java (`pom.xml`) etc. as needed.
- CloudFix prompt uses `apply_patch` which can fail on complex multi-hunk edits. The `edit` tool would be more reliable but requires a different model backend configuration.
