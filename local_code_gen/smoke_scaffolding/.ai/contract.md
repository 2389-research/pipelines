# Smoke Test — Tiny Go HTTP Service

This contract is intentionally tiny. It exists to exercise `write_scaffolding_files` end-to-end through tracker's actual Anthropic adapter, not to specify a real project.

## Stack

- Go 1.23
- `net/http` standard library only
- No third-party dependencies

## Verbatim files

The following files MUST be produced exactly as written. They are scaffolding — `write_scaffolding_files` should emit them via its JSON envelope and let tracker write them to disk.

### `go.mod` (verbatim)

```gomod
module example.com/smoke

go 1.23
```

### `cmd/server/main.go` (verbatim)

```go
package main

import (
	"net/http"
)

func main() {
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	_ = http.ListenAndServe(":8080", nil)
}
```

### `.gitignore` (verbatim)

```gitignore
bin/
*.exe
.DS_Store
```

## Algorithmic files (qwen's job, NOT scaffolding)

The following files are described here for completeness but should NOT be written by `write_scaffolding_files` — they're algorithmic and would be qwen's per-sprint job in a real flow:

- `internal/handlers/health_test.go` — table-driven tests for the /health endpoint, asserting status code 200 and JSON body shape.

If `write_scaffolding_files` includes this file, that's a bug in scaffolding-vs-algorithmic classification.

## Validation

After the smoke test, the workspace should contain (workspace-relative paths):

- `go.mod`
- `cmd/server/main.go`
- `.gitignore`
- `.ai/scaffolding_manifest.txt` listing exactly those three paths, in some order

It should NOT contain:

- `internal/handlers/health_test.go` (algorithmic — should be omitted)
- Any doubled-prefix paths
