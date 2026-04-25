package domain

import "time"

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

func NewSession(id, workspaceRoot string) *Session {
	s := &Session{
		ID:            id,
		WorkspaceRoot: workspaceRoot,
		Agents:        make(map[string]*Agent),
		CreatedAt:     time.Now(),
	}

	rootAgent := NewAgent(id+"-root", id, "")
	s.Agents[rootAgent.ID] = rootAgent
	s.RootAgentID = rootAgent.ID

	return s
}
