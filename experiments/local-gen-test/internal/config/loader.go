package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config file: %w", err)
	}

	expanded := os.ExpandEnv(string(data))

	var cfg Config
	if err := yaml.Unmarshal([]byte(expanded), &cfg); err != nil {
		return nil, fmt.Errorf("parse config file: %w", err)
	}

	applyDefaults(&cfg)

	return &cfg, nil
}

func Validate(cfg *Config) error {
	if len(cfg.WorkspaceRoots) == 0 {
		return fmt.Errorf("workspace_roots is required")
	}
	return nil
}
