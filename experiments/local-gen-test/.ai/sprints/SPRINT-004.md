# Sprint 004 — Configuration & CLI Entrypoints (enriched spec)

## Scope
YAML config loading with env var substitution, validation, and defaults.
Wire four CLI subcommand stubs. Update main.go dispatch to include new commands.

## Non-goals
- No actual TUI, web server, or runtime logic — stubs only
- No auth system

## Dependencies
- Sprint 002: `cmd/agent/main.go` exists with os.Args dispatch and `printUsage`
- Sprint 003: `internal/domain` types exist (Budget, ProviderPolicy)

## Go/runtime conventions
- Module: `agent`
- Package `config`: all files in `internal/config/` use `package config`
- YAML library: `gopkg.in/yaml.v3`
- Env var substitution: `os.ExpandEnv(string(rawBytes))` applied before unmarshal
- Error wrapping: `fmt.Errorf("...: %w", err)`

## Module dependency
Add to `go.mod` via:
```bash
go get gopkg.in/yaml.v3
```

## Type definitions

### `internal/config/config.go`
```go
type Config struct {
    WorkspaceRoots []string         `yaml:"workspace_roots"`
    Server         ServerConfig     `yaml:"server"`
    Providers      []ProviderConfig `yaml:"providers"`
    Routing        RoutingConfig    `yaml:"routing"`
    ToolPolicy     ToolPolicyConfig `yaml:"tool_policy"`
    Budget         BudgetConfig     `yaml:"budget"`
}

type ServerConfig struct {
    Bind string `yaml:"bind"`
}

type ProviderConfig struct {
    Name   string   `yaml:"name"`
    APIKey string   `yaml:"api_key"`
    Models []string `yaml:"models"`
}

type RoutingConfig struct {
    DefaultProvider string `yaml:"default_provider"`
    DefaultModel    string `yaml:"default_model"`
}

type ToolPolicyConfig struct {
    AutoApprove bool     `yaml:"auto_approve"`
    DeniedTools []string `yaml:"denied_tools"`
}

type BudgetConfig struct {
    MaxTokens           int    `yaml:"max_tokens"`
    MaxWallClock        string `yaml:"max_wall_clock"`
    MaxToolCalls        int    `yaml:"max_tool_calls"`
    MaxForkDepth        int    `yaml:"max_fork_depth"`
    MaxChildConcurrency int    `yaml:"max_child_concurrency"`
}
```

### `internal/config/defaults.go`
```go
func DefaultConfig() Config {
    return Config{
        Server: ServerConfig{
            Bind: "127.0.0.1:8080",
        },
        Routing: RoutingConfig{
            DefaultProvider: "openai",
        },
        ToolPolicy: ToolPolicyConfig{
            AutoApprove: false,
            DeniedTools: []string{},
        },
        Budget: BudgetConfig{
            MaxTokens:           100000,
            MaxWallClock:        "30m",
            MaxToolCalls:        50,
            MaxForkDepth:        3,
            MaxChildConcurrency: 2,
        },
    }
}

func applyDefaults(cfg *Config) {
    d := DefaultConfig()
    if cfg.Server.Bind == "" {
        cfg.Server.Bind = d.Server.Bind
    }
    if cfg.Routing.DefaultProvider == "" {
        cfg.Routing.DefaultProvider = d.Routing.DefaultProvider
    }
    if cfg.Budget.MaxTokens == 0 {
        cfg.Budget.MaxTokens = d.Budget.MaxTokens
    }
    if cfg.Budget.MaxWallClock == "" {
        cfg.Budget.MaxWallClock = d.Budget.MaxWallClock
    }
    if cfg.Budget.MaxToolCalls == 0 {
        cfg.Budget.MaxToolCalls = d.Budget.MaxToolCalls
    }
    if cfg.Budget.MaxForkDepth == 0 {
        cfg.Budget.MaxForkDepth = d.Budget.MaxForkDepth
    }
    if cfg.Budget.MaxChildConcurrency == 0 {
        cfg.Budget.MaxChildConcurrency = d.Budget.MaxChildConcurrency
    }
}
```

### `internal/config/loader.go`
```go
func Load(path string) (*Config, error)
func Validate(cfg *Config) error
```

`Load` algorithm:
1. `os.ReadFile(path)` → raw bytes; return error if fails
2. `expanded := os.ExpandEnv(string(data))` — substitutes `${VAR}` and `$VAR`
3. Start from `DefaultConfig()` as base
4. `yaml.Unmarshal([]byte(expanded), &cfg)` → return error if fails
5. `applyDefaults(&cfg)`
6. Return `&cfg, nil`

`Validate` algorithm:
1. If `len(cfg.WorkspaceRoots) == 0`, return `fmt.Errorf("workspace_roots is required")`
2. Return nil

## CLI stubs

### `cmd/agent/cmd_tui.go`
```go
package main

import (
    "fmt"
    "io"
)

func runTUI(stdout io.Writer) int {
    fmt.Fprintln(stdout, "tui: not yet implemented")
    return 0
}
```

### `cmd/agent/cmd_serve.go`
```go
package main

import (
    "fmt"
    "io"
)

func runServe(stdout io.Writer) int {
    fmt.Fprintln(stdout, "serve: not yet implemented")
    return 0
}
```

### `cmd/agent/cmd_run.go`
```go
package main

import (
    "fmt"
    "io"
)

func runRun(stdout io.Writer) int {
    fmt.Fprintln(stdout, "run: not yet implemented")
    return 0
}
```

### `cmd/agent/main.go` — update dispatch and printUsage
Add cases for `tui`, `serve`, `run` to the existing switch. Update `printUsage` to list all commands.

Copy this `printUsage` verbatim:
```go
func printUsage(w io.Writer) {
    fmt.Fprintln(w, "agent <command>")
    fmt.Fprintln(w, "")
    fmt.Fprintln(w, "Available commands:")
    fmt.Fprintln(w, "  tui      launch terminal UI")
    fmt.Fprintln(w, "  serve    start HTTP/SSE server")
    fmt.Fprintln(w, "  run      headless session execution")
    fmt.Fprintln(w, "  doctor   environment diagnostics")
    fmt.Fprintln(w, "  version  print version")
}
```

Add to the switch in `run()`:
```go
case "tui":
    return runTUI(stdout)
case "serve":
    return runServe(stdout)
case "run":
    return runRun(stdout)
```

### `configs/agent.example.yaml` — write verbatim
```yaml
# Agent configuration example
# Copy to agent.yaml and edit before running

workspace_roots:
  - /path/to/your/repo

server:
  bind: "127.0.0.1:8080"

providers:
  - name: openai
    api_key: ${OPENAI_API_KEY}
    models:
      - gpt-4o
      - gpt-4o-mini
  - name: ollama
    api_key: ""
    models:
      - qwen3:8b
      - gemma3:4b

routing:
  default_provider: openai
  default_model: gpt-4o

tool_policy:
  auto_approve: false
  denied_tools: []

budget:
  max_tokens: 100000
  max_wall_clock: "30m"
  max_tool_calls: 50
  max_fork_depth: 3
  max_child_concurrency: 2
```

## Imports per file

**`internal/config/config.go`**
```go
// no imports
```

**`internal/config/defaults.go`**
```go
// no imports
```

**`internal/config/loader.go`**
```go
import (
    "fmt"
    "os"

    "gopkg.in/yaml.v3"
)
```

**`internal/config/config_test.go`**
```go
import (
    "os"
    "path/filepath"
    "testing"
)
```

**`cmd/agent/cmd_tui.go`**, **`cmd_serve.go`**, **`cmd_run.go`**
```go
import (
    "fmt"
    "io"
)
```

**`cmd/agent/main.go`** — existing file, only add cases and update printUsage

## Test plan

### `internal/config/config_test.go`
```go
func TestConfigLoad(t *testing.T)
func TestConfigValidation(t *testing.T)
func TestConfigDefaults(t *testing.T)
func TestBudgetConfig(t *testing.T)
```

**`TestConfigLoad`** — write YAML to temp file, set env var, call Load, assert values:
```go
t.Setenv("TEST_API_KEY", "sk-test")
content := `
workspace_roots:
  - /tmp/repo
providers:
  - name: openai
    api_key: ${TEST_API_KEY}
`
path := filepath.Join(t.TempDir(), "agent.yaml")
os.WriteFile(path, []byte(content), 0o600)
cfg, err := Load(path)
// assert err == nil
// assert cfg.WorkspaceRoots[0] == "/tmp/repo"
// assert cfg.Providers[0].APIKey == "sk-test"
```

**`TestConfigValidation`** — empty WorkspaceRoots returns error:
```go
cfg := &Config{}
err := Validate(cfg)
// assert err != nil
// assert strings.Contains(err.Error(), "workspace_roots")
```

**`TestConfigDefaults`** — minimal config gets defaults applied:
```go
content := "workspace_roots:\n  - /tmp\n"
// Load, assert cfg.Server.Bind == "127.0.0.1:8080"
// assert cfg.Budget.MaxTokens == 100000
// assert cfg.Budget.MaxWallClock == "30m"
```

**`TestBudgetConfig`** — explicit budget values are loaded:
```go
content := `
workspace_roots:
  - /tmp
budget:
  max_tokens: 50000
  max_tool_calls: 10
`
// Load, assert cfg.Budget.MaxTokens == 50000
// assert cfg.Budget.MaxToolCalls == 10
```

## Rules
- `config.go` has no imports — all types use only built-in Go types and struct tags
- `applyDefaults` is unexported — only called from `Load`
- `Load` starts from `DefaultConfig()` as the base, then unmarshals on top — do NOT unmarshal into zero-value Config
- `cmd_tui.go`, `cmd_serve.go`, `cmd_run.go` use `io.Writer` parameter matching Sprint 002's `run()` signature
- `main.go` is an existing file — only add the three new switch cases and replace `printUsage` body; do not rewrite the whole file
- `configs/agent.example.yaml` is a top-level directory — create `configs/` if it doesn't exist
- Do NOT add build tags to any file

## New files
- `internal/config/config.go`
- `internal/config/loader.go`
- `internal/config/defaults.go`
- `internal/config/config_test.go`
- `cmd/agent/cmd_tui.go`
- `cmd/agent/cmd_serve.go`
- `cmd/agent/cmd_run.go`
- `configs/agent.example.yaml`

## Modified files
- `cmd/agent/main.go` — add three switch cases (`tui`, `serve`, `run`) and replace `printUsage` body; see the verbatim code blocks in the CLI stubs section above

## Expected Artifacts
- `internal/config/config.go`
- `internal/config/loader.go`
- `internal/config/defaults.go`
- `internal/config/config_test.go`
- `cmd/agent/cmd_tui.go`
- `cmd/agent/cmd_serve.go`
- `cmd/agent/cmd_run.go`
- `cmd/agent/main.go`
- `configs/agent.example.yaml`

## DoD
- [ ] `go test ./internal/config/ -run TestConfigLoad -v` passes
- [ ] `go test ./internal/config/ -run TestConfigValidation -v` passes
- [ ] `go test ./internal/config/ -run TestConfigDefaults -v` passes
- [ ] `go test ./internal/config/ -run TestBudgetConfig -v` passes
- [ ] `go build -o agent ./cmd/agent/` succeeds
- [ ] `./agent --help` lists tui, serve, run, doctor, version

## Validation
```bash
go get gopkg.in/yaml.v3
go test ./internal/config/ -v
go build -o agent ./cmd/agent/
./agent --help
```
