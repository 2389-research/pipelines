# Sprint 001 — External Services & Dev Environment (enriched spec)

## Scope
Set up SQLite as the project persistence backend for the Go runtime. Add a small connection helper in `internal/store` that opens a SQLite database, forces WAL mode, enables foreign keys, and verifies both settings. Add a separate health-check function that validates a database path is usable. Document the required environment variables and include a minimal `docker-compose.yml` for an optional dev container.

## Non-goals
- No schema migrations in this sprint
- No domain tables in this sprint
- No blob store in this sprint
- No HTTP server or health endpoint in this sprint
- No repository-wide config loader in this sprint
- No production container image in this sprint

## Requirements
- Bootstrap only; enables later SQLite-backed sprints
- Supports product-spec requirement for SQLite metadata store

## Dependencies
- Sprint 000 owns repo/bootstrap concerns such as existing `go.mod`
- This sprint assumes the module already exists

## Go/runtime conventions
- Language: Go
- All Go files under `internal/store/` use `package store`
- Use the standard library `database/sql`
- Use the pure-Go SQLite driver `modernc.org/sqlite`
- Do **not** use `github.com/mattn/go-sqlite3`
- All tests use the standard `testing` package
- All temp files and directories in tests must come from `t.TempDir()`
- All error wrapping uses `fmt.Errorf("...: %w", err)`

## Module dependency
This sprint requires this module dependency to exist in `go.mod`:

```text
modernc.org/sqlite v1.34.5
```

If `go.mod` already exists but does not include that dependency, add it with:

```bash
go get modernc.org/sqlite@v1.34.5
```

Do not invent or change the module path in this sprint.

## Interface contract

```go
// internal/store/db.go
package store

import "database/sql"

func OpenDB(path string) (*sql.DB, error)
```

```go
// internal/store/health.go
package store

import "context"

func HealthCheck(ctx context.Context, path string) error
```

## File-by-file contract

### `internal/store/db.go`
Implement exactly one exported function:

```go
func OpenDB(path string) (*sql.DB, error)
```

Behavior:
1. Reject an empty or whitespace-only path.
2. Clean the path with `filepath.Clean`.
3. Open SQLite with `sql.Open("sqlite", cleanedPath)`.
4. Set both pool sizes to 1:
   - `db.SetMaxOpenConns(1)`
   - `db.SetMaxIdleConns(1)`
5. Create a `context.WithTimeout(context.Background(), 2*time.Second)`.
6. Call `db.PingContext(ctx)` to force the connection to open.
7. Execute `PRAGMA journal_mode = WAL;`.
8. Execute `PRAGMA foreign_keys = ON;`.
9. Verify `PRAGMA journal_mode;` returns the string `"wal"`.
10. Verify `PRAGMA foreign_keys;` returns the integer `1`.
11. If any step fails, close the database handle before returning the error.
12. On success, return the open `*sql.DB`.

Required error cases:
- empty path -> return an error immediately
- missing parent directory -> return an error from `PingContext` or `PRAGMA` setup
- invalid/corrupt SQLite file -> return an error during `PingContext` or `PRAGMA` verification

Exact verification snippets to copy:

```go
var journalMode string
if err := db.QueryRowContext(ctx, `PRAGMA journal_mode;`).Scan(&journalMode); err != nil {
    _ = db.Close()
    return nil, fmt.Errorf("query journal_mode pragma: %w", err)
}
if journalMode != "wal" {
    _ = db.Close()
    return nil, fmt.Errorf("unexpected journal_mode: %s", journalMode)
}

var foreignKeys int
if err := db.QueryRowContext(ctx, `PRAGMA foreign_keys;`).Scan(&foreignKeys); err != nil {
    _ = db.Close()
    return nil, fmt.Errorf("query foreign_keys pragma: %w", err)
}
if foreignKeys != 1 {
    _ = db.Close()
    return nil, fmt.Errorf("unexpected foreign_keys pragma: %d", foreignKeys)
}
```

### `internal/store/health.go`
Implement exactly one exported function:

```go
func HealthCheck(ctx context.Context, path string) error
```

Behavior:
1. Call `OpenDB(path)`.
2. If `OpenDB` fails, return `fmt.Errorf("open db: %w", err)`.
3. Defer `db.Close()`.
4. Call `db.PingContext(ctx)`.
5. Run `SELECT 1` with `QueryRowContext` and scan into an `int`.
6. If the scanned value is not `1`, return `fmt.Errorf("unexpected health query result: %d", value)`.
7. Otherwise return `nil`.

Exact query snippet to copy:

```go
var value int
if err := db.QueryRowContext(ctx, `SELECT 1`).Scan(&value); err != nil {
    return fmt.Errorf("query db: %w", err)
}
if value != 1 {
    return fmt.Errorf("unexpected health query result: %d", value)
}
return nil
```

### `internal/store/db_test.go`
Create one test file in the same package: `package store`.

Top-level tests and exact subtest names:

```go
func TestOpenDB(t *testing.T)
func TestHealthCheck(t *testing.T)
```

`TestOpenDB` must contain these exact subtests:
- `"enables WAL mode"`
- `"enables foreign keys"`
- `"returns a usable handle"`

`TestHealthCheck` must contain these exact subtests:
- `"returns nil for a valid database path"`
- `"returns an error for a missing parent directory"`
- `"returns an error for a corrupt sqlite file"`

Test helper functions to add in the same file:

```go
func newTempDBPath(t *testing.T) string
func queryPragmaString(t *testing.T, db *sql.DB, pragma string) string
func queryPragmaInt(t *testing.T, db *sql.DB, pragma string) int
```

Helper behavior:
- `newTempDBPath` returns `filepath.Join(t.TempDir(), "agent.sqlite")`
- `queryPragmaString` runs `PRAGMA <name>;` and scans a string
- `queryPragmaInt` runs `PRAGMA <name>;` and scans an int
- Each helper calls `t.Helper()`
- On any query error, helpers call `t.Fatalf(...)`

Test algorithms:

**`TestOpenDB/enables WAL mode`**
1. Create a temp database path.
2. Call `OpenDB(path)`.
3. Register `t.Cleanup(func() { _ = db.Close() })`.
4. Query `PRAGMA journal_mode;` using `queryPragmaString`.
5. Assert the result equals `"wal"`.

**`TestOpenDB/enables foreign keys`**
1. Create a temp database path.
2. Call `OpenDB(path)`.
3. Register cleanup.
4. Query `PRAGMA foreign_keys;` using `queryPragmaInt`.
5. Assert the result equals `1`.

**`TestOpenDB/returns a usable handle`**
1. Create a temp database path.
2. Call `OpenDB(path)`.
3. Register cleanup.
4. Run `db.Exec(`CREATE TABLE health_probe (id INTEGER PRIMARY KEY)` )`.
5. Fail the test if the exec returns an error.

Use this exact statement string:

```go
`CREATE TABLE health_probe (id INTEGER PRIMARY KEY)`
```

**`TestHealthCheck/returns nil for a valid database path`**
1. Create a temp database path.
2. Call `OpenDB(path)` once so the file definitely exists and is valid.
3. Close that handle.
4. Create `ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)` and `defer cancel()`.
5. Call `HealthCheck(ctx, path)`.
6. Assert the error is `nil`.

**`TestHealthCheck/returns an error for a missing parent directory`**
1. Start from `t.TempDir()`.
2. Build a path inside a child directory that does not exist:
   `filepath.Join(root, "does-not-exist", "agent.sqlite")`
3. Create a 2-second timeout context.
4. Call `HealthCheck(ctx, path)`.
5. Assert the error is non-nil.

**`TestHealthCheck/returns an error for a corrupt sqlite file`**
1. Create a temp directory.
2. Write a file named `corrupt.sqlite` whose contents are exactly `[]byte("not a sqlite database")`.
3. Use permission `0o600`.
4. Create a 2-second timeout context.
5. Call `HealthCheck(ctx, corruptPath)`.
6. Assert the error is non-nil.

### `.env.example`
Write this file verbatim:

```dotenv
AGENT_DB_PATH=.data/agent.sqlite
OPENAI_API_KEY=
OLLAMA_HOST=http://127.0.0.1:11434
```

### `docker-compose.yml`
Write this file verbatim:

```yaml
services:
  dev:
    image: golang:1.24
    working_dir: /workspace
    volumes:
      - .:/workspace
      - agent-data:/data
    environment:
      AGENT_DB_PATH: /data/agent.sqlite
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      OLLAMA_HOST: http://host.docker.internal:11434
    command: ["sleep", "infinity"]

volumes:
  agent-data:
```

## Imports per file

Copy these import blocks verbatim.

**`internal/store/db.go`**
```go
import (
    "context"
    "database/sql"
    "fmt"
    "path/filepath"
    "strings"
    "time"

    _ "modernc.org/sqlite"
)
```

**`internal/store/health.go`**
```go
import (
    "context"
    "fmt"
)
```

**`internal/store/db_test.go`**
```go
import (
    "context"
    "database/sql"
    "os"
    "path/filepath"
    "testing"
    "time"
)
```

**`.env.example`** — no imports

**`docker-compose.yml`** — no imports

## Algorithm notes

### `OpenDB(path string) (*sql.DB, error)`
Copy this structure exactly:

```go
if strings.TrimSpace(path) == "" {
    return nil, fmt.Errorf("db path is required")
}

cleanedPath := filepath.Clean(path)
db, err := sql.Open("sqlite", cleanedPath)
if err != nil {
    return nil, fmt.Errorf("open sqlite database: %w", err)
}

db.SetMaxOpenConns(1)
db.SetMaxIdleConns(1)

ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
defer cancel()

if err := db.PingContext(ctx); err != nil {
    _ = db.Close()
    return nil, fmt.Errorf("ping sqlite database: %w", err)
}

if _, err := db.ExecContext(ctx, `PRAGMA journal_mode = WAL;`); err != nil {
    _ = db.Close()
    return nil, fmt.Errorf("enable wal mode: %w", err)
}

if _, err := db.ExecContext(ctx, `PRAGMA foreign_keys = ON;`); err != nil {
    _ = db.Close()
    return nil, fmt.Errorf("enable foreign keys: %w", err)
}
```

After that block, append the exact verification snippet from the `internal/store/db.go` section above, then `return db, nil`.

### `HealthCheck(ctx context.Context, path string) error`
Copy this structure exactly:

```go
db, err := OpenDB(path)
if err != nil {
    return fmt.Errorf("open db: %w", err)
}
defer db.Close()

if err := db.PingContext(ctx); err != nil {
    return fmt.Errorf("ping db: %w", err)
}
```

After that block, append the exact `SELECT 1` snippet from the `internal/store/health.go` section above.

### `newTempDBPath(t *testing.T) string`
Exact body:

```go
t.Helper()
return filepath.Join(t.TempDir(), "agent.sqlite")
```

### `queryPragmaString(t *testing.T, db *sql.DB, pragma string) string`
Exact body:

```go
t.Helper()
var value string
query := "PRAGMA " + pragma + ";"
if err := db.QueryRow(query).Scan(&value); err != nil {
    t.Fatalf("query pragma %s: %v", pragma, err)
}
return value
```

### `queryPragmaInt(t *testing.T, db *sql.DB, pragma string) int`
Exact body:

```go
t.Helper()
var value int
query := "PRAGMA " + pragma + ";"
if err := db.QueryRow(query).Scan(&value); err != nil {
    t.Fatalf("query pragma %s: %v", pragma, err)
}
return value
```

## Test plan

Create `internal/store/db_test.go` with exactly these top-level tests:

```go
func TestOpenDB(t *testing.T)
func TestHealthCheck(t *testing.T)
```

And exactly these subtests:

```text
TestOpenDB/enables WAL mode
TestOpenDB/enables foreign keys
TestOpenDB/returns a usable handle
TestHealthCheck/returns nil for a valid database path
TestHealthCheck/returns an error for a missing parent directory
TestHealthCheck/returns an error for a corrupt sqlite file
```

Expected assertions:
- `journal_mode` must equal `"wal"`
- `foreign_keys` must equal `1`
- `CREATE TABLE health_probe ...` must succeed
- `HealthCheck(validPath)` must return `nil`
- `HealthCheck(missingParentDirPath)` must return a non-nil error
- `HealthCheck(corruptFilePath)` must return a non-nil error

## Rules
- Do not create schema tables beyond the test-only `health_probe` table
- Do not create directories automatically inside `OpenDB`
- Do not hide missing-directory failures with `os.MkdirAll`
- Do not add any exported functions other than `OpenDB` and `HealthCheck`
- Do not add extra files under `internal/store/` beyond `db.go`, `health.go`, and `db_test.go`
- Keep tests in package `store`, not `store_test`
- Use the exact imports listed above
- Use the exact test names and subtest names listed above
- Use `context.WithTimeout(..., 2*time.Second)` in all health-check tests
- Keep `docker-compose.yml` minimal; it is only a dev helper, not a SQLite service

## Expected Artifacts
- `internal/store/db.go`
- `internal/store/health.go`
- `internal/store/db_test.go`
- `docker-compose.yml`
- `.env.example`

## DoD
- [ ] `internal/store.OpenDB(path)` opens a SQLite database in WAL mode with foreign keys enabled
- [ ] `OpenDB` verifies WAL mode and foreign keys before returning success
- [ ] `HealthCheck(ctx, path)` returns `nil` for a valid database path
- [ ] `HealthCheck(ctx, path)` returns an error for a missing parent directory path
- [ ] `HealthCheck(ctx, path)` returns an error for a corrupt SQLite file
- [ ] `.env.example` documents `AGENT_DB_PATH`, `OPENAI_API_KEY`, `OLLAMA_HOST`
- [ ] `go test ./internal/store/ -run TestOpenDB -v` passes
- [ ] `go test ./internal/store/ -v` passes

## Validation

```bash
go test ./internal/store/ -run TestOpenDB -v
go test ./internal/store/ -v
```
