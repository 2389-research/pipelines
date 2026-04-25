package config

type Config struct {
	WorkspaceRoots []string         `yaml:"workspace_roots"`
	Server         ServerConfig     `yaml:"server"`
	Providers      []ProviderConfig `yaml:"providers"`
	Routing        RoutingConfig    `yaml:"routing"`
	ToolPolicy     ToolPolicyConfig `yaml:"tool_policy"`
	Budget         BudgetConfig     `yaml:"budget"`
}

type ServerConfig struct {
	Bind string `yaml:"bind"`
}

type ProviderConfig struct {
	Name   string   `yaml:"name"`
	APIKey string   `yaml:"api_key"`
	Models []string `yaml:"models"`
}

type RoutingConfig struct {
	DefaultProvider string `yaml:"default_provider"`
	DefaultModel    string `yaml:"default_model"`
}

type ToolPolicyConfig struct {
	AutoApprove bool     `yaml:"auto_approve"`
	DeniedTools []string `yaml:"denied_tools"`
}

type BudgetConfig struct {
	MaxTokens           int    `yaml:"max_tokens"`
	MaxWallClock        string `yaml:"max_wall_clock"`
	MaxToolCalls        int    `yaml:"max_tool_calls"`
	MaxForkDepth        int    `yaml:"max_fork_depth"`
	MaxChildConcurrency int    `yaml:"max_child_concurrency"`
}
