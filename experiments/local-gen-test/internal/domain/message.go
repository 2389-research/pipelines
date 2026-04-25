package domain

import "time"

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
