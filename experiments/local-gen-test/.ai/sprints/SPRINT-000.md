
# Sprint 000 — Project Scaffold & Toolchain (enriched spec)

## Scope
Initialize the repository as a Go module for a single local-first binary named `agent`, using Go 1.24, standard-library-first packaging, and the package layout suggested by the product spec. This sprint creates only the scaffold: a compilable `cmd/agent` stub, empty-but-buildable `internal/` package directories via package marker files, a Makefile with exact bootstrap targets, pinned linter and Tailwind configuration, and a CI workflow that runs the same build/test/vet/lint steps locally required by the thin sprint. No runtime logic, HTTP handlers, Bubble Tea UI, storage, providers, or tools are implemented here.

## Non-goals
- No domain logic, orchestration, provider adapters, tool execution, storage, or UI behavior
- No HTTP endpoints, SSE, templates, SQLite schema, or event types
- No external service connections, API keys, or network calls in Go code
- No generated Tailwind output committed; only the input stylesheet and config are created
- No tests beyond allowing `go test ./...` to succeed with zero tests

## Runtime and conventions
- **Go** — `go 1.24.0`, module mode, standard `go test`, `go vet`, `go build`
- **Module path** — `github.com/example/agent`
- **Node/Tailwind toolchain** — `tailwindcss v3.4.13` invoked through `npx`
- **Linting** — `golangci-lint` config file compatible with `golangci-lint run`
- **CI** — GitHub Actions on `ubuntu-latest`, Go setup via `actions/setup-go@v5`
- **Conventions**
  - all Go packages use lowercase package names matching their directories
  - placeholder packages must compile and may contain only a package declaration plus doc comment
  - `cmd/agent/main.go` must be the only executable entrypoint in this sprint
  - do not add any exported symbols except `main`
  - Tailwind output path is `web/static/styles.css`, but that file is not created in this sprint

## Dependency declaration
Use these exact bootstrap commands to establish resolver-managed artifacts:
- `go mod init github.com/example/agent`
- `go mod tidy`
- `npm exec --yes tailwindcss@3.4.13 -i web/input.css -o web/static/styles.css`

Do not hand-author `go.sum`; let `go mod tidy` create or leave it absent if empty. The enriched executor should still list `go.sum` as an expected resolver-managed artifact.

## Interface contract

```go
// cmd/agent/main.go
package main

func main()
```

## File-by-file contract

### `go.mod`
Create a Go module file with exactly:
- module path `github.com/example/agent`
- `go 1.24.0`
- no `require` block if there are no dependencies
- no comments

Exact content:
- line 1: `module github.com/example/agent`
- blank line
- line 3: `go 1.24.0`

### `cmd/agent/main.go`
Provide the minimal compilable CLI stub.
Behavior:
1. Use package `main`.
2. Import only `fmt`.
3. `main()` must call `fmt.Println("agent bootstrap stub")`.
4. Do not parse args, read env, or exit non-zero.
5. Do not add helper functions.

### `internal/app/doc.go`
Create a package marker file.
Behavior:
1. Package name is `app`.
2. File contains only a package doc comment and the package declaration.
3. No imports, vars, consts, types, or functions.

Use this exact doc comment text:
`// Package app contains application assembly glue for the local-first agent.`

### `internal/core/doc.go`
Use package `core`.
Exact doc comment:
`// Package core contains the domain runtime primitives for sessions, agents, and events.`

### `internal/core/events/doc.go`
Use package `events`.
Exact doc comment:
`// Package events contains typed event definitions and event stream helpers.`

### `internal/core/orchestrator/doc.go`
Use package `orchestrator`.
Exact doc comment:
`// Package orchestrator contains the event-first execution loop.`

### `internal/core/agents/doc.go`
Use package `agents`.
Exact doc comment:
`// Package agents contains agent lifecycle and fork management types.`

### `internal/core/messages/doc.go`
Use package `messages`.
Exact doc comment:
`// Package messages contains canonical message and content-part types.`

### `internal/provider/doc.go`
Use package `provider`.
Exact doc comment:
`// Package provider contains provider-independent model adapter contracts.`

### `internal/provider/openai/doc.go`
Use package `openai`.
Exact doc comment:
`// Package openai contains the OpenAI-compatible provider adapter.`

### `internal/provider/anthropic/doc.go`
Use package `anthropic`.
Exact doc comment:
`// Package anthropic contains the Anthropic Claude provider adapter.`

### `internal/provider/gemini/doc.go`
Use package `gemini`.
Exact doc comment:
`// Package gemini contains the Google Gemini provider adapter.`

### `internal/provider/ollama/doc.go`
Use package `ollama`.
Exact doc comment:
`// Package ollama contains the local Ollama provider adapter.`

### `internal/tools/doc.go`
Use package `tools`.
Exact doc comment:
`// Package tools contains tool registration and shared tool contracts.`

### `internal/tools/search/doc.go`
Use package `search`.
Exact doc comment:
`// Package search contains the workspace search tool.`

### `internal/tools/read/doc.go`
Use package `read`.
Exact doc comment:
`// Package read contains the workspace file read tool.`

### `internal/tools/write/doc.go`
Use package `write`.
Exact doc comment:
`// Package write contains the workspace file write tool.`

### `internal/tools/bash/doc.go`
Use package `bash`.
Exact doc comment:
`// Package bash contains the bounded shell execution tool.`

### `internal/tools/glob/doc.go`
Use package `glob`.
Exact doc comment:
`// Package glob contains the workspace file enumeration tool.`

### `internal/tools/webfetch/doc.go`
Use package `webfetch`.
Exact doc comment:
`// Package webfetch contains the network fetch and normalization tool.`

### `internal/workspace/doc.go`
Use package `workspace`.
Exact doc comment:
`// Package workspace contains workspace root, snapshot, and overlay helpers.`

### `internal/store/doc.go`
Use package `store`.
Exact doc comment:
`// Package store contains SQLite and blob persistence adapters.`

### `internal/tui/doc.go`
Use package `tui`.
Exact doc comment:
`// Package tui contains Bubble Tea UI models and adapters.`

### `internal/web/doc.go`
Use package `web`.
Exact doc comment:
`// Package web contains the local HTTP, htmx, and SSE server.`

### `internal/web/templates/.keep`
Create an empty file so the templates directory exists in version control.
Behavior:
1. Zero bytes preferred.
2. No newline required.

### `internal/config/doc.go`
Use package `config`.
Exact doc comment:
`// Package config contains config loading and validation helpers.`

### `internal/policy/doc.go`
Use package `policy`.
Exact doc comment:
`// Package policy contains tool approval and safety policy rules.`

### `web/tailwind.config.js`
Create a CommonJS Tailwind config.
Behavior:
1. Export with `module.exports = { ... }`.
2. `content` must be exactly:
   - `"./templates/**/*.html"`
   - `"./static/**/*.js"`
3. `darkMode` must be `"class"`.
4. `theme.extend` must be an empty object.
5. `plugins` must be an empty array.
6. Do not require any plugin packages.

Exact content:
```js
module.exports = {
  content: [
    "./templates/**/*.html",
    "./static/**/*.js",
  ],
  darkMode: "class",
  theme: {
    extend: {},
  },
  plugins: [],
};
```

### `web/input.css`
Create the Tailwind input stylesheet with exactly three directives in this order:
1. `@tailwind base;`
2. `@tailwind components;`
3. `@tailwind utilities;`

Each directive must be on its own line.

### `web/static/.keep`
Create an empty file so the output directory exists before Tailwind runs.

### `Makefile`
Create a POSIX-make-compatible Makefile.
Behavior:
1. First target must be `build`.
2. Declare `.PHONY: build test vet lint tailwind ci`.
3. `build` recipe must run exactly: `go build ./cmd/agent/`
4. `test` recipe must run exactly: `go test ./...`
5. `vet` recipe must run exactly: `go vet ./...`
6. `lint` recipe must run exactly: `golangci-lint run`
7. `tailwind` recipe must run exactly: `npx tailwindcss -i web/input.css -o web/static/styles.css`
8. `ci` recipe must run, in order, these four make targets on separate recipe lines:
   - `$(MAKE) build`
   - `$(MAKE) test`
   - `$(MAKE) vet`
   - `$(MAKE) lint`
9. Use tabs, not spaces, for recipe indentation.
10. Do not add other targets.

### `.golangci.yml`
Create a minimal valid YAML config.
Behavior:
1. Set `run.timeout` to `2m`.
2. Set `issues.max-issues-per-linter` to `0`.
3. Set `issues.max-same-issues` to `0`.
4. Enable only:
   - `errcheck`
   - `gosimple`
   - `govet`
   - `ineffassign`
   - `staticcheck`
   - `unused`
5. Do not add exclusions, presets, or formatter sections.

Exact content:
```yaml
run:
  timeout: 2m

linters:
  enable:
    - errcheck
    - gosimple
    - govet
    - ineffassign
    - staticcheck
    - unused

issues:
  max-issues-per-linter: 0
  max-same-issues: 0
```

### `.github/workflows/ci.yml`
Create a GitHub Actions workflow.
Behavior:
1. Workflow name must be `ci`.
2. Trigger on:
   - push
   - pull_request
3. Single job key must be `build-test-lint`.
4. Job runs on `ubuntu-latest`.
5. Steps, in exact order:
   - `actions/checkout@v4`
   - `actions/setup-go@v5` with `go-version: '1.24.0'`
   - install golangci-lint using `golangci/golangci-lint-action@v6` with `version: v1.60.3` and `args: --version`
   - run `go build ./cmd/agent/`
   - run `go test ./...`
   - run `go vet ./...`
   - run `golangci-lint run`
6. Do not add matrix builds, caches, Node setup, or Tailwind build to CI in this sprint.

Use this exact YAML shape and values:
```yaml
name: ci

on:
  push:
  pull_request:

jobs:
  build-test-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-go@v5
        with:
          go-version: '1.24.0'

      - uses: golangci/golangci-lint-action@v6
        with:
          version: v1.60.3
          args: --version

      - name: Build
        run: go build ./cmd/agent/

      - name: Test
        run: go test ./...

      - name: Vet
        run: go vet ./...

      - name: Lint
        run: golangci-lint run
```

### `go.sum`
Resolver-managed artifact.
Behavior:
1. Do not invent contents.
2. If `go mod tidy` produces no `go.sum`, that is acceptable for this sprint.
3. If a `go.sum` is emitted by the toolchain, commit the exact generated bytes.

## Imports per file

**`cmd/agent/main.go`**
```go
import "fmt"
```

All `doc.go` files must have no import block.

## Algorithm notes

**main()**
1. Call `fmt.Println("agent bootstrap stub")`.
2. Return normally.

## Test plan

Because the thin sprint permits zero tests, do not create any `_test.go` files in this sprint. Validation is command-based and CI-config-based.

## New files
- `go.mod`
- `cmd/agent/main.go`
- `internal/app/doc.go`
- `internal/core/doc.go`
- `internal/core/events/doc.go`
- `internal/core/orchestrator/doc.go`
- `internal/core/agents/doc.go`
- `internal/core/messages/doc.go`
- `internal/provider/doc.go`
- `internal/provider/openai/doc.go`
- `internal/provider/anthropic/doc.go`
- `internal/provider/gemini/doc.go`
- `internal/provider/ollama/doc.go`
- `internal/tools/doc.go`
- `internal/tools/search/doc.go`
- `internal/tools/read/doc.go`
- `internal/tools/write/doc.go`
- `internal/tools/bash/doc.go`
- `internal/tools/glob/doc.go`
- `internal/tools/webfetch/doc.go`
- `internal/workspace/doc.go`
- `internal/store/doc.go`
- `internal/tui/doc.go`
- `internal/web/doc.go`
- `internal/web/templates/.keep`
- `internal/config/doc.go`
- `internal/policy/doc.go`
- `Makefile`
- `.golangci.yml`
- `.github/workflows/ci.yml`
- `web/tailwind.config.js`
- `web/input.css`
- `web/static/.keep`

## Modified files
- None

## Rules
- Do not add any Go dependencies beyond the standard library in this sprint
- Do not add exported functions, types, vars, or constants beyond `main`
- Do not create any `_test.go` files
- Do not add any files beyond those listed in `## New files`
- Do not implement CLI subcommands yet; the product-spec modes `tui`, `serve`, `run`, and `doctor` are deferred
- Use the exact module path `github.com/example/agent`
- Use the exact stub output string `agent bootstrap stub`
- Use the exact imports, YAML keys, target names, workflow step order, and Tailwind config values listed above
- Do not commit `web/static/styles.css`; only ensure the command can output there
- Do not hand-author `go.sum`; generate it only via `go mod tidy` if needed
- Keep all placeholder packages compilable with only package docs and declarations

## DoD
- [ ] `go build ./cmd/agent/` produces a binary without errors
- [ ] `go test ./...` runs successfully with zero test files
- [ ] `go vet ./...` reports no issues
- [ ] `golangci-lint run` passes with zero findings against the created scaffold
- [ ] `.github/workflows/ci.yml` exists and defines build + test + lint steps
- [ ] `npx tailwindcss -i web/input.css -o web/static/styles.css` completes
- [ ] `Makefile` exposes the exact targets `build`, `test`, `vet`, `lint`, `tailwind`, and `ci`
- [ ] the `internal/` package structure exists for the suggested package layout from the product spec