You are working in `run.working_dir`.

Read `.ai/sprint_plan.md` and `.ai/spec_analysis.md`.

Write one SPRINT-NNN.md file under `.ai/sprints/` for each sprint in the plan.
IDs are zero-padded 3-digit (001, 002, ...). Never write sprint files to the project root.

## Purpose

These sprint docs are executed by a local LLM (qwen or gemma via Ollama) with no internet
access, no tool calls, and a single generation pass per file. The model cannot make design
decisions, look up library docs, or resolve ambiguity. Every choice must be pre-decided and
expressed as exact code syntax — not English descriptions.

A well-written sprint leaves the local model zero ambiguous choices.

## Required sections — write ALL of these in every sprint

### 1. Scope
2-4 sentences: what this sprint delivers.

### 2. Non-goals
Bulleted list of what is explicitly excluded. Reference which later sprint handles it.

### 3. Dependencies
List prior sprints by number and state exactly what they provide that this sprint relies on.
Example: "Sprint 001: module name is `agent`, `internal/store` package with `OpenDB(path string) (*sql.DB, error)`"

### 4. Runtime and conventions
Establish the rules for this sprint:
- Language version and runtime (e.g. "Go 1.24", "Node.js with type: module")
- Package name for each new package introduced
- Error wrapping style (e.g. `fmt.Errorf("context: %w", err)`)
- Test helper conventions (e.g. `t.Helper()`, `t.TempDir()`)
- Import style (e.g. `.ts` extensions, never `.js`)
- Any framework or library choices that are not yet established

### 5. Type definitions / Data model
For every new type, struct, interface, or SQL table this sprint introduces:
- Write the complete definition in actual language syntax (Go struct, TypeScript interface, SQL DDL)
- Include all fields, tags, and constraints
- Do not summarise — write the full definition

### 6. Interface contract
List every exported function, method, and constructor this sprint adds.
Use exact language syntax — no prose.
Example (Go): `func OpenDB(path string) (*sql.DB, error)`
Example (TS): `export function createTestApp(): TestApp`

### 7. File-by-file contract
For each file this sprint produces, write a subsection `### path/to/file.go` containing:
- The exact function or exported symbol it contains
- Numbered behavior steps for non-trivial logic (1. validate input, 2. open connection, ...)
- Verbatim code blocks for any snippet where exact syntax matters
  (error messages, query strings, struct literals, switch cases)
- Explicit "copy this exactly" or "write this verbatim" where appropriate

**What "verbatim code" means:** Provide the complete function body, not a numbered step list.
A step list like "1. call OpenDB, 2. defer Close, 3. run SELECT 1" still leaves the model
choosing variable names, error message strings, and return placement. A verbatim body
removes all those choices. See the Algorithm notes section for the required density level.

### 8. Imports per file
For every file, list the exact import block the local model must use.
Use actual syntax. Mark files with no imports explicitly.
Do not omit this section — import drift is the most common local model failure mode.

### 9. Algorithm notes
For any function whose implementation is non-obvious:
- Provide the complete function body using "Copy this structure exactly" or "Copy this body exactly"
- Verbatim means full implementation, not abbreviated pseudocode or numbered steps
- State what NOT to do when there is a common wrong alternative

**Example of the required density (Go):**

The following excerpt from a real sprint doc shows the level of detail expected.
`HealthCheck` is a four-line function; the sprint doc still gives the full body:

```go
// internal/store/health.go — copy this body exactly
func HealthCheck(ctx context.Context, path string) error {
    db, err := OpenDB(path)
    if err != nil {
        return fmt.Errorf("open db: %w", err)
    }
    defer db.Close()

    if err := db.PingContext(ctx); err != nil {
        return fmt.Errorf("ping db: %w", err)
    }

    var value int
    if err := db.QueryRowContext(ctx, `SELECT 1`).Scan(&value); err != nil {
        return fmt.Errorf("query db: %w", err)
    }
    if value != 1 {
        return fmt.Errorf("unexpected health query result: %d", value)
    }
    return nil
}
```

Every variable name, error string, and return placement is fixed. The local model
transcribes; it does not design.

### 10. Test plan
List every test function and every subtest by exact name.
Use actual test function syntax:
  Go: `func TestOpenDB(t *testing.T)` with subtests `"enables WAL mode"`, `"returns error for empty path"`
  TS: `test('GET /health returns 200 with full HealthResponse')`
Describe what each test asserts in one line.

### 11. Rules
Negative constraints — things the local model must NOT do.
State these explicitly even when they seem obvious.
Examples:
- "Do not use mattn/go-sqlite3 — use modernc.org/sqlite"
- "All relative imports use .ts extension, never .js"
- "Do not call os.Exit inside runDoctor — only main() exits"
- "applyDefaults is unexported — only called from Load"

### 12. New files / Modified files
Use two separate sections:
## New files
- `path/to/new/file.go`

## Modified files
- `path/to/existing/file.go` — describe what changes and reference the verbatim code blocks above

If all files are new, use ## New files only.

### 13. DoD
5-10 items. Each must be machine-verifiable — an exact command or a binary observable outcome.
Good: `go test ./internal/store/ -run TestOpenDB -v passes`
Bad: "SQLite store works correctly"

### 14. Validation
Exact bash commands to verify the sprint is complete. One command per line.

## Cross-sprint consistency rule

Write sprints in order (001 first, then 002, etc.).
Before writing each sprint N, read all previously written `.ai/sprints/SPRINT-*.md` files.
Do not redefine types, functions, or constants already established in prior sprints.
Reference them by their exact exported name.
If sprint N modifies an existing file, state only what changes — do not re-specify what stays the same.

## Decision rule

Where the spec or sprint plan is ambiguous about implementation details, make a concrete
choice and commit to it. Do not hedge with "you may use X or Y". Do not write "choose based
on your preference". The local model has no preference — it needs one answer.

## Syntax rule

Every function signature, import block, type definition, and test name must appear in actual
language syntax — not English. "Implement a health check function" is forbidden.
`func HealthCheck(ctx context.Context, path string) error` is correct.
