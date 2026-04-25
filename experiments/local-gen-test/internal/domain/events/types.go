package events

import "time"

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

type SessionCreatedPayload struct {
	SessionID string
}

type AgentForkedPayload struct {
	ParentID string
	ChildID  string
}

type MessageDeltaPayload struct {
	MessageID string
	Delta     string
}

type MessageCompletedPayload struct {
	MessageID string
}

type ToolRequestedPayload struct {
	ToolCallID string
	Name       string
}

type ToolStartedPayload struct {
	ToolCallID string
}

type ToolStdoutPayload struct {
	ToolCallID string
	Data       string
}

type ToolCompletedPayload struct {
	ToolCallID string
	ExitCode   int
}

type PatchCreatedPayload struct {
	PatchID string
	Path    string
}

type MergeProposedPayload struct {
	MergeID      string
	ChildAgentID string
}

type MergeAppliedPayload struct {
	MergeID string
}

type RunFailedPayload struct {
	Reason string
}
