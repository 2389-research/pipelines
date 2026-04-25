# Sprint 003 — Core Domain Model & Event System (enriched spec)

## Scope
Define all core domain types and the typed event system with an in-memory event bus.
Enforce the agent lifecycle state machine. No persistence, no UI, no provider code.

## Non-goals
- No database writes, no HTTP handlers, no provider adapters
- No tool implementations — only the ToolCall type

## Dependencies
- Sprint 001: module `agent`, `internal/store` package exists
- Sprint 002: `cmd/agent` entrypoint exists

## Go/runtime conventions
- Module: `agent`
- Package `domain`: all files in `internal/domain/` use `package domain`
- Package `events`: files in `internal/domain/events/` use `package events`
- `events` may import `domain`; `domain` must NOT import `events`
- All IDs are `string`; use `time.Time` for timestamps
- Error wrapping: `fmt.Errorf("...: %w", err)`
- All test helpers call `t.Helper()`

## Type definitions

### `internal/domain/session.go`
```go
type Session struct {
    ID             string
    WorkspaceRoot  string
    Agents         map[string]*Agent
    RootAgentID    string
    AttachmentIDs  []string
    ProviderPolicy ProviderPolicy
    CreatedAt      time.Time
}

type ProviderPolicy struct {
    Default  string
    Fallback []string
}

func NewSession(id, workspaceRoot string) *Session
```

`NewSession` algorithm:
1. Create `Session` with given `id` and `workspaceRoot`
2. Set `Agents` to `make(map[string]*Agent)`
3. Set `CreatedAt` to `time.Now()`
4. Create root agent: `NewAgent(id+"-root", id, "")` (agentID, sessionID, parentID="")
5. Add root agent to `Agents` map
6. Set `RootAgentID` to root agent ID
7. Return the session

### `internal/domain/agent.go`
```go
type AgentState string

const (
    AgentStateIdle                AgentState = "idle"
    AgentStateQueued              AgentState = "queued"
    AgentStateRunning             AgentState = "running"
    AgentStateWaitingToolApproval AgentState = "waiting_for_tool_approval"
    AgentStateWaitingMerge        AgentState = "waiting_for_merge"
    AgentStateCompleted           AgentState = "completed"
    AgentStateFailed              AgentState = "failed"
    AgentStateCancelled           AgentState = "cancelled"
)

type Agent struct {
    ID        string
    SessionID string
    ParentID  string
    State     AgentState
    Messages  []Message
    Summary   string
    Provider  string
    Model     string
    Budget    Budget
    CreatedAt time.Time
}

func NewAgent(id, sessionID, parentID string) *Agent
func (a *Agent) Transition(next AgentState) error
func (a *Agent) IsTerminal() bool
```

`NewAgent`: creates Agent with `State: AgentStateIdle`, `CreatedAt: time.Now()`, empty `Messages` slice.

`IsTerminal`: returns true if `State` is `AgentStateCompleted`, `AgentStateFailed`, or `AgentStateCancelled`.

`Transition` — valid transitions (all others return error):
```go
var validTransitions = map[AgentState][]AgentState{
    AgentStateIdle:                {AgentStateQueued, AgentStateCancelled},
    AgentStateQueued:              {AgentStateRunning, AgentStateCancelled},
    AgentStateRunning:             {AgentStateWaitingToolApproval, AgentStateWaitingMerge, AgentStateCompleted, AgentStateFailed, AgentStateCancelled},
    AgentStateWaitingToolApproval: {AgentStateRunning, AgentStateCancelled},
    AgentStateWaitingMerge:        {AgentStateRunning, AgentStateCancelled},
    AgentStateCompleted:           {},
    AgentStateFailed:              {},
    AgentStateCancelled:           {},
}
```

`Transition` algorithm:
1. Look up allowed next states for `a.State`
2. If `next` is not in the allowed list, return `fmt.Errorf("invalid transition %s → %s", a.State, next)`
3. Set `a.State = next`, return nil

### `internal/domain/message.go`
```go
type Role string

const (
    RoleUser      Role = "user"
    RoleAssistant Role = "assistant"
    RoleSystem    Role = "system"
    RoleTool      Role = "tool"
)

type Message struct {
    ID            string
    AgentID       string
    Role          Role
    Content       string
    AttachmentIDs []string
    ToolCallIDs   []string
    CreatedAt     time.Time
}
```

### `internal/domain/attachment.go`
```go
type Attachment struct {
    ID       string
    Filename string
    MIME     string
    Size     int64
    SHA256   string
    Width    int
    Height   int
    BlobPath string
    Source   string // "tui", "web", "api"
}
```

### `internal/domain/toolcall.go`
```go
type ToolCallState string

const (
    ToolCallStateRequested ToolCallState = "requested"
    ToolCallStateApproved  ToolCallState = "approved"
    ToolCallStateDenied    ToolCallState = "denied"
    ToolCallStateRunning   ToolCallState = "running"
    ToolCallStateCompleted ToolCallState = "completed"
    ToolCallStateFailed    ToolCallState = "failed"
)

type ToolCall struct {
    ID        string
    AgentID   string
    MessageID string
    Name      string
    Input     json.RawMessage
    State     ToolCallState
    CreatedAt time.Time
}
```

### `internal/domain/artifact.go`
```go
type ArtifactKind string

const (
    ArtifactKindMessage    ArtifactKind = "message"
    ArtifactKindPatchSet   ArtifactKind = "patch_set"
    ArtifactKindFile       ArtifactKind = "file"
    ArtifactKindAttachment ArtifactKind = "attachment"
    ArtifactKindTestOutput ArtifactKind = "test_output"
    ArtifactKindSummary    ArtifactKind = "summary"
)

type Artifact struct {
    ID        string
    AgentID   string
    SessionID string
    Kind      ArtifactKind
    Path      string
    Content   []byte
    CreatedAt time.Time
}
```

### `internal/domain/patch.go`
```go
type Patch struct {
    ID          string
    AgentID     string
    SessionID   string
    Path        string
    UnifiedDiff string
    OldSHA256   string
    NewSHA256   string
    CreatedAt   time.Time
}
```

### `internal/domain/merge.go`
```go
type MergeState string

const (
    MergeStateProposed MergeState = "proposed"
    MergeStateApplied  MergeState = "applied"
    MergeStateRejected MergeState = "rejected"
)

type Merge struct {
    ID            string
    SessionID     string
    ChildAgentID  string
    ParentAgentID string
    PatchIDs      []string
    State         MergeState
    ProposedAt    time.Time
    AppliedAt     *time.Time
}
```

### `internal/domain/budget.go`
```go
type Budget struct {
    MaxTokens           int
    MaxWallClock        time.Duration
    MaxToolCalls        int
    MaxForkDepth        int
    MaxChildConcurrency int

    UsedTokens    int
    UsedToolCalls int
    StartedAt     time.Time
}

func (b *Budget) TokensExceeded() bool
func (b *Budget) WallClockExceeded() bool
func (b *Budget) ToolCallsExceeded() bool
```

`TokensExceeded`: returns `b.MaxTokens > 0 && b.UsedTokens > b.MaxTokens`
`WallClockExceeded`: returns `b.MaxWallClock > 0 && time.Since(b.StartedAt) > b.MaxWallClock`
`ToolCallsExceeded`: returns `b.MaxToolCalls > 0 && b.UsedToolCalls > b.MaxToolCalls`

### `internal/domain/events/types.go`
```go
type EventKind string

const (
    KindSessionCreated       EventKind = "session.created"
    KindAgentForked          EventKind = "agent.forked"
    KindMessageDelta         EventKind = "message.delta"
    KindMessageCompleted     EventKind = "message.completed"
    KindToolRequested        EventKind = "tool.requested"
    KindToolStarted          EventKind = "tool.started"
    KindToolStdout           EventKind = "tool.stdout"
    KindToolCompleted        EventKind = "tool.completed"
    KindPatchCreated         EventKind = "patch.created"
    KindMergeProposed        EventKind = "merge.proposed"
    KindMergeApplied         EventKind = "merge.applied"
    KindRunFailed            EventKind = "run.failed"
)

type Event struct {
    ID         string
    Kind       EventKind
    SessionID  string
    AgentID    string
    Seq        int64
    OccurredAt time.Time
    Payload    any
}

type SessionCreatedPayload  struct{ SessionID string }
type AgentForkedPayload     struct{ ParentID, ChildID string }
type MessageDeltaPayload    struct{ MessageID, Delta string }
type MessageCompletedPayload struct{ MessageID string }
type ToolRequestedPayload   struct{ ToolCallID, Name string }
type ToolStartedPayload     struct{ ToolCallID string }
type ToolStdoutPayload      struct{ ToolCallID, Data string }
type ToolCompletedPayload   struct{ ToolCallID string; ExitCode int }
type PatchCreatedPayload    struct{ PatchID, Path string }
type MergeProposedPayload   struct{ MergeID, ChildAgentID string }
type MergeAppliedPayload    struct{ MergeID string }
type RunFailedPayload       struct{ Reason string }
```

### `internal/domain/events/bus.go`
```go
type Handler func(Event)

type Bus struct {
    mu       sync.RWMutex
    handlers map[EventKind][]Handler
}

func NewBus() *Bus
func (b *Bus) Subscribe(kind EventKind, h Handler)
func (b *Bus) Publish(e Event)
```

`NewBus`: returns `&Bus{handlers: make(map[EventKind][]Handler)}`

`Subscribe` algorithm:
1. Lock `b.mu`
2. Append `h` to `b.handlers[kind]`
3. Unlock

`Publish` algorithm:
1. RLock `b.mu`
2. Copy `b.handlers[e.Kind]` to local slice
3. RUnlock
4. Call each handler in the local slice with `e`

## Imports per file

**`internal/domain/session.go`**
```go
import "time"
```

**`internal/domain/agent.go`**
```go
import (
    "fmt"
    "time"
)
```

**`internal/domain/message.go`**
```go
import "time"
```

**`internal/domain/attachment.go`**
```go
// no imports
```

**`internal/domain/toolcall.go`**
```go
import (
    "encoding/json"
    "time"
)
```

**`internal/domain/artifact.go`**
```go
import "time"
```

**`internal/domain/patch.go`**
```go
import "time"
```

**`internal/domain/merge.go`**
```go
import "time"
```

**`internal/domain/budget.go`**
```go
import "time"
```

**`internal/domain/events/types.go`**
```go
import "time"
```

**`internal/domain/events/bus.go`**
```go
import "sync"
```

**`internal/domain/domain_test.go`**
```go
import (
    "testing"
    "time"
)
```

**`internal/domain/events/bus_test.go`**
```go
import (
    "sync"
    "testing"
    "time"
)
```

## Test plan

### `internal/domain/domain_test.go`
```go
func TestAgentStateTransitions(t *testing.T)
func TestSessionCreation(t *testing.T)
func TestBudget(t *testing.T)
```

**`TestAgentStateTransitions`** subtests:
- `"idle to queued is valid"` — `NewAgent`, `Transition(AgentStateQueued)`, assert nil error
- `"idle to running is invalid"` — `NewAgent`, `Transition(AgentStateRunning)`, assert non-nil error
- `"terminal state rejects all transitions"` — transition to `AgentStateCompleted`, then `Transition(AgentStateCancelled)`, assert non-nil error
- `"full happy path"` — idle → queued → running → completed, assert no errors

**`TestSessionCreation`** subtests:
- `"creates root agent in idle state"` — `NewSession("s1", "/tmp")`, assert `RootAgentID != ""`, root agent state is `AgentStateIdle`
- `"root agent has no parent"` — assert root agent `ParentID == ""`

**`TestBudget`** subtests:
- `"tokens not exceeded when under limit"` — `Budget{MaxTokens: 100, UsedTokens: 50}`, assert `TokensExceeded() == false`
- `"tokens exceeded when over limit"` — `Budget{MaxTokens: 100, UsedTokens: 101}`, assert `TokensExceeded() == true`
- `"zero max means no limit"` — `Budget{MaxTokens: 0, UsedTokens: 9999}`, assert `TokensExceeded() == false`
- `"wall clock exceeded"` — `Budget{MaxWallClock: time.Millisecond, StartedAt: time.Now().Add(-time.Second)}`, assert `WallClockExceeded() == true`
- `"tool calls exceeded"` — `Budget{MaxToolCalls: 5, UsedToolCalls: 6}`, assert `ToolCallsExceeded() == true`

### `internal/domain/events/bus_test.go`
```go
func TestBus(t *testing.T)
```

**`TestBus`** subtests:
- `"subscriber receives published event"` — `NewBus()`, subscribe to `KindSessionCreated`, publish event, assert handler was called with correct `Kind`
- `"subscriber only receives subscribed kind"` — subscribe to `KindSessionCreated`, publish `KindAgentForked`, assert handler was NOT called
- `"multiple subscribers all receive event"` — subscribe two handlers to same kind, publish once, assert both called
- `"concurrent publish is safe"` — subscribe one handler that increments a counter, publish 100 events concurrently via goroutines, assert counter == 100 using `sync.WaitGroup`

## Rules
- `domain` package must NOT import `events` package — events imports domain only
- `toolcall.go` imports `encoding/json` for `json.RawMessage` — do not use `interface{}` or `any` instead
- `Transition` must not mutate state before validating — validate first, assign second
- `Bus.Publish` must copy handlers under read lock before calling them — do not hold lock while calling handlers
- Terminal states (`completed`, `failed`, `cancelled`) have empty transition lists — `Transition` must return an error for any next state
- All `time.Time` fields use `time.Now()` at creation; `AppliedAt *time.Time` in Merge is a pointer (nil until applied)
- Do not add a `go.sum` entry — module is already initialized

## Expected Artifacts
- `internal/domain/session.go`
- `internal/domain/agent.go`
- `internal/domain/message.go`
- `internal/domain/attachment.go`
- `internal/domain/artifact.go`
- `internal/domain/toolcall.go`
- `internal/domain/patch.go`
- `internal/domain/merge.go`
- `internal/domain/budget.go`
- `internal/domain/events/types.go`
- `internal/domain/events/bus.go`
- `internal/domain/domain_test.go`
- `internal/domain/events/bus_test.go`

## DoD
- [ ] All 12 domain event kinds defined in `events/types.go`
- [ ] Agent lifecycle state machine enforced via `Transition()`
- [ ] `go test ./internal/domain/ -run TestAgentStateTransitions -v` passes
- [ ] `go test ./internal/domain/events/ -run TestBus -v` passes
- [ ] `go test ./internal/domain/ -run TestSessionCreation -v` passes
- [ ] `go test ./internal/domain/ -run TestBudget -v` passes
- [ ] `go build ./...` succeeds; `go vet ./internal/domain/...` clean

## Validation
```bash
go test ./internal/domain/... -v
go vet ./internal/domain/...
```
