package domain

import (
	"fmt"
	"time"
)

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

func NewAgent(id, sessionID, parentID string) *Agent {
	return &Agent{
		ID:        id,
		SessionID: sessionID,
		ParentID:  parentID,
		State:     AgentStateIdle,
		Messages:  []Message{},
		CreatedAt: time.Now(),
	}
}

func (a *Agent) Transition(next AgentState) error {
	allowed, ok := validTransitions[a.State]
	if !ok {
		return fmt.Errorf("invalid transition %s → %s", a.State, next)
	}
	for _, s := range allowed {
		if s == next {
			a.State = next
			return nil
		}
	}
	return fmt.Errorf("invalid transition %s → %s", a.State, next)
}

func (a *Agent) IsTerminal() bool {
	return a.State == AgentStateCompleted || a.State == AgentStateFailed || a.State == AgentStateCancelled
}
