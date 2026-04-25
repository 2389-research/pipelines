package domain

import "time"

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
