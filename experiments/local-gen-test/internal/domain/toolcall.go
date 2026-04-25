package domain

import (
	"encoding/json"
	"time"
)

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
