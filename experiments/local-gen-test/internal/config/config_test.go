package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestConfigLoad(t *testing.T) {
	t.Setenv("TEST_API_KEY", "sk-test")
	content := `
workspace_roots:
  - /tmp/repo
providers:
  - name: openai
    api_key: ${TEST_API_KEY}
`
	path := filepath.Join(t.TempDir(), "agent.yaml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load error: %v", err)
	}

	if len(cfg.WorkspaceRoots) == 0 || cfg.WorkspaceRoots[0] != "/tmp/repo" {
		t.Errorf("expected workspace_roots[0] to be /tmp/repo, got %v", cfg.WorkspaceRoots)
	}

	if len(cfg.Providers) == 0 || cfg.Providers[0].APIKey != "sk-test" {
		t.Errorf("expected providers[0].api_key to be sk-test, got %v", cfg.Providers)
	}
}

func TestConfigValidation(t *testing.T) {
	cfg := &Config{}
	err := Validate(cfg)
	if err == nil {
		t.Fatal("expected error for empty workspace_roots, got nil")
	}
	if !contains(err.Error(), "workspace_roots") {
		t.Errorf("expected error to contain 'workspace_roots', got %v", err)
	}
}

func TestConfigDefaults(t *testing.T) {
	content := "workspace_roots:\n  - /tmp\n"
	path := filepath.Join(t.TempDir(), "agent.yaml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load error: %v", err)
	}

	if cfg.Server.Bind != "127.0.0.1:8080" {
		t.Errorf("expected default server bind, got %s", cfg.Server.Bind)
	}
	if cfg.Budget.MaxTokens != 100000 {
		t.Errorf("expected default max_tokens, got %d", cfg.Budget.MaxTokens)
	}
	if cfg.Budget.MaxWallClock != "30m" {
		t.Errorf("expected default max_wall_clock, got %s", cfg.Budget.MaxWallClock)
	}
}

func TestBudgetConfig(t *testing.T) {
	content := `
workspace_roots:
  - /tmp
budget:
  max_tokens: 50000
  max_tool_calls: 10
`
	path := filepath.Join(t.TempDir(), "agent.yaml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load error: %v", err)
	}

	if cfg.Budget.MaxTokens != 50000 {
		t.Errorf("expected max_tokens to be 50000, got %d", cfg.Budget.MaxTokens)
	}
	if cfg.Budget.MaxToolCalls != 10 {
		t.Errorf("expected max_tool_calls to be 10, got %d", cfg.Budget.MaxToolCalls)
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(substr) == 0 || func() bool {
		for i := 0; i <= len(s)-len(substr); i++ {
			if s[i:i+len(substr)] == substr {
				return true
			}
		}
		return false
	}())
}
