package domain

// Attachment represents a file or media attachment associated with a session.
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
