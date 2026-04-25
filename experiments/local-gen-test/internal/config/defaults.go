package config

func DefaultConfig() Config {
	return Config{
		Server: ServerConfig{
			Bind: "127.0.0.1:8080",
		},
		Routing: RoutingConfig{
			DefaultProvider: "openai",
		},
		ToolPolicy: ToolPolicyConfig{
			AutoApprove: false,
			DeniedTools: []string{},
		},
		Budget: BudgetConfig{
			MaxTokens:           100000,
			MaxWallClock:        "30m",
			MaxToolCalls:        50,
			MaxForkDepth:        3,
			MaxChildConcurrency: 2,
		},
	}
}

func applyDefaults(cfg *Config) {
	d := DefaultConfig()
	if cfg.Server.Bind == "" {
		cfg.Server.Bind = d.Server.Bind
	}
	if cfg.Routing.DefaultProvider == "" {
		cfg.Routing.DefaultProvider = d.Routing.DefaultProvider
	}
	if cfg.Budget.MaxTokens == 0 {
		cfg.Budget.MaxTokens = d.Budget.MaxTokens
	}
	if cfg.Budget.MaxWallClock == "" {
		cfg.Budget.MaxWallClock = d.Budget.MaxWallClock
	}
	if cfg.Budget.MaxToolCalls == 0 {
		cfg.Budget.MaxToolCalls = d.Budget.MaxToolCalls
	}
	if cfg.Budget.MaxForkDepth == 0 {
		cfg.Budget.MaxForkDepth = d.Budget.MaxForkDepth
	}
	if cfg.Budget.MaxChildConcurrency == 0 {
		cfg.Budget.MaxChildConcurrency = d.Budget.MaxChildConcurrency
	}
}
