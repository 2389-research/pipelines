package domain

import "time"

type Budget struct {
	MaxTokens           int
	MaxWallClock        time.Duration
	MaxToolCalls        int
	MaxForkDepth        int
	MaxChildConcurrency int

	UsedTokens    int
	UsedToolCalls int
	StartedAt     time.Time
}

func (b *Budget) TokensExceeded() bool {
	return b.MaxTokens > 0 && b.UsedTokens > b.MaxTokens
}

func (b *Budget) WallClockExceeded() bool {
	return b.MaxWallClock > 0 && time.Since(b.StartedAt) > b.MaxWallClock
}

func (b *Budget) ToolCallsExceeded() bool {
	return b.MaxToolCalls > 0 && b.UsedToolCalls > b.MaxToolCalls
}
