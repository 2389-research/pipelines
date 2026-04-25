package domain

import "time"

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
