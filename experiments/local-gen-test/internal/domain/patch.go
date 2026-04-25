package domain

import "time"

// Patch represents a unified diff associated with an agent and session.
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
