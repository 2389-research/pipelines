package domain

import (
	"testing"
	"time"
)

func TestAgentStateTransitions(t *testing.T) {
	t.Helper()

	t.Run("idle to queued is valid", func(t *testing.T) {
		t.Helper()
		a := NewAgent("a1", "s1", "")
		err := a.Transition(AgentStateQueued)
		if err != nil {
			t.Fatalf("expected nil error, got %v", err)
		}
		if a.State != AgentStateQueued {
			t.Fatalf("expected state queued, got %s", a.State)
		}
	})

	t.Run("idle to running is invalid", func(t *testing.T) {
		t.Helper()
		a := NewAgent("a2", "s1", "")
		err := a.Transition(AgentStateRunning)
		if err == nil {
			t.Fatal("expected non-nil error, got nil")
		}
		if a.State != AgentStateIdle {
			t.Fatalf("expected state to remain idle, got %s", a.State)
		}
	})

	t.Run("terminal state rejects all transitions", func(t *testing.T) {
		t.Helper()
		a := NewAgent("a3", "s1", "")
		err := a.Transition(AgentStateQueued)
		if err != nil {
			t.Fatalf("expected nil error moving to queued, got %v", err)
		}
		err = a.Transition(AgentStateRunning)
		if err != nil {
			t.Fatalf("expected nil error moving to running, got %v", err)
		}
		err = a.Transition(AgentStateCompleted)
		if err != nil {
			t.Fatalf("expected nil error moving to completed, got %v", err)
		}
		if a.State != AgentStateCompleted {
			t.Fatalf("expected state completed, got %s", a.State)
		}

		for _, next := range []AgentState{
			AgentStateIdle,
			AgentStateQueued,
			AgentStateRunning,
			AgentStateCompleted,
			AgentStateCancelled,
		} {
			err = a.Transition(next)
			if err == nil {
				t.Fatalf("expected non-nil error for completed to %s, got nil", next)
			}
			if a.State != AgentStateCompleted {
				t.Fatalf("expected state to remain completed, got %s", a.State)
			}
		}
	})

	t.Run("full happy path", func(t *testing.T) {
		t.Helper()
		a := NewAgent("a4", "s1", "")
		err := a.Transition(AgentStateQueued)
		if err != nil {
			t.Fatalf("idle to queued: %v", err)
		}
		err = a.Transition(AgentStateRunning)
		if err != nil {
			t.Fatalf("queued to running: %v", err)
		}
		err = a.Transition(AgentStateCompleted)
		if err != nil {
			t.Fatalf("running to completed: %v", err)
		}
		if a.State != AgentStateCompleted {
			t.Fatalf("expected state completed, got %s", a.State)
		}
	})
}

func TestSessionCreation(t *testing.T) {
	t.Helper()

	t.Run("creates root agent in idle state", func(t *testing.T) {
		t.Helper()
		s := NewSession("s1", "/tmp")
		if s.RootAgentID == "" {
			t.Fatal("expected RootAgentID to be set")
		}
		_, exists := s.Agents[s.RootAgentID]
		if !exists {
			t.Fatal("expected root agent to be in Agents map")
		}
		if s.Agents[s.RootAgentID].State != AgentStateIdle {
			t.Fatalf("expected root agent state idle, got %s", s.Agents[s.RootAgentID].State)
		}
	})

	t.Run("root agent has no parent", func(t *testing.T) {
		t.Helper()
		s := NewSession("s2", "/tmp")
		rootAgent := s.Agents[s.RootAgentID]
		if rootAgent.ParentID != "" {
			t.Fatalf("expected root agent ParentID to be empty, got %s", rootAgent.ParentID)
		}
	})
}

func TestBudget(t *testing.T) {
	t.Helper()

	t.Run("tokens not exceeded when under limit", func(t *testing.T) {
		t.Helper()
		b := Budget{MaxTokens: 100, UsedTokens: 50}
		if b.TokensExceeded() {
			t.Fatal("expected TokensExceeded to be false")
		}
	})

	t.Run("tokens exceeded when over limit", func(t *testing.T) {
		t.Helper()
		b := Budget{MaxTokens: 100, UsedTokens: 101}
		if !b.TokensExceeded() {
			t.Fatal("expected TokensExceeded to be true")
		}
	})

	t.Run("zero max means no limit", func(t *testing.T) {
		t.Helper()
		b := Budget{MaxTokens: 0, UsedTokens: 9999}
		if b.TokensExceeded() {
			t.Fatal("expected TokensExceeded to be false")
		}
	})

	t.Run("wall clock exceeded", func(t *testing.T) {
		t.Helper()
		b := Budget{MaxWallClock: time.Millisecond, StartedAt: time.Now().Add(-time.Second)}
		if !b.WallClockExceeded() {
			t.Fatal("expected WallClockExceeded to be true")
		}
	})

	t.Run("tool calls exceeded", func(t *testing.T) {
		t.Helper()
		b := Budget{MaxToolCalls: 5, UsedToolCalls: 6}
		if !b.ToolCallsExceeded() {
			t.Fatal("expected ToolCallsExceeded to be true")
		}
	})
}
