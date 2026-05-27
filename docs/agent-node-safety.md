# Agent-node safety in `.dip` pipelines

> Verified against `tracker v0.29.2` / `dippin v0.27.0` engine source by three independent reviewers, 2026-05-18. The findings below shape what's safe and what's a foot-gun when designing `agent` nodes for the workflows in this repo.

> **Update — dippin v0.32.0:** The original "no language-level primitive to suppress agent tool access" finding (line 7 below) is now historical. [dippin-lang#41](https://github.com/2389-research/dippin-lang/issues/41) closed in v0.32.0 with the `tool_access: none` agent-node field, which strips the model's tool catalog at the language level. Use it on acknowledge-only agents (Start, Exit, status reporters). The TL;DR mitigations below are still useful — `tool_access: none` and `max_turns: 1` are complementary (catalog bound + turn-count bound). A broader rewrite of this doc is tracked in [#20](https://github.com/2389-research/pipelines/issues/20).

## TL;DR

`agent` nodes on the **native backend** (the default) always have full read/write/bash/edit/glob/grep tool access. There is no language-level primitive in dippin to suppress that. So:

1. **`Start` and `Exit` should never be `agent` nodes with `prompt:` bodies.** Use `tool` nodes (or bare `agent` with no prompt) — the v0.28.2 runaway-agent bug came from exactly this anti-pattern.
2. **For any "summarize / format the output / write a closing message" need: prefer a `tool` node** templating from safe `ctx.*` keys and disk files. Zero LLM, zero exposure.
3. **If you genuinely need an LLM at a node that should not touch files,** use `backend: claude-code` with explicit `disallowed_tools` — the native backend silently drops those attributes.
4. **Don't trust `${ctx.last_response}` content** when designing downstream agent prompts — it's a cross-node prompt-injection vector.

## Why the obvious mitigations don't work

### `max_turns: 1` does not bound damage within the one turn

The engine's agent loop is:

```go
for turn := 1; turn <= MaxTurns; turn++ {
    response := LLMCall(prompt, tools, ...)
    if response.HasToolCalls() {
        executeToolCalls(response.ToolCalls)   // runs ALL tool calls sequentially
    }
    // turn++ happens here; loop exits if turn > MaxTurns
}
```

A model can emit `[bash("rm -rf data/"), write("malicious.py", "..."), bash("./malicious.py")]` in a single response. All three execute *before* the cap is checked. Setting `max_turns: 1` prevents iterative drift across turns (which was the 10-minute Go-project-implementation failure mode of the original v0.28.2 incident), but it does not prevent a single-turn smash-and-grab.

Source: `tracker/agent/session.go:213, 232-277, 334`; `tracker/agent/session_run.go:276-320`.

### The native backend always ships the full tool catalog

`tracker/agent/profile.go:9-31` unconditionally registers `Read`, `Write`, `Edit`, `ApplyPatch`, `Glob`, `GrepSearch`, `Bash` (OpenAI gets the same minus `Edit`) for every native-backend agent. `tracker/agent/session_run.go:120` passes the full registry as the request's `Tools:` array. There is no branch that strips tools based on node config.

The `disallowed_tools` / `allowed_tools` node attributes do exist (`pipeline/handlers/codergen.go:295-302`) but plumb **only** into `buildClaudeCodeConfig`. The native backend (`pipeline/handlers/backend_native.go:108-126`) silently drops them. Dippin has no `tool_choice: none`, no `tools: []`, no `text_only: true` directive in the language.

The Anthropic translator does honor `tool_choice: none` correctly (`tracker/llm/anthropic/translate.go:182-184`) — it skips the `tools` array entirely — but **dippin never sets that field** for native-backend agents. So the field exists in the LLM types layer but is unreachable from `.dip` source today.

### The system prompt advertises file tools to the model

Every native-backend agent's system prompt is prefixed with:

> "File tool arguments (read, write, edit, glob, grep_search) MUST use paths relative to the working directory."

(`tracker/agent/session_run.go:24-31`)

Your `prompt:` body is appended *after* this. Writing "do not run tools" in user space fights an in-system-channel hint that names them. Empirically (per the v0.28.2 incident), this loses.

### `${ctx.last_response}` flows unsanitized between agent nodes

The `${ctx.*}` safe-key allowlist (`outcome`, `preferred_label`, `human_response`, `interview_answers`) only applies to **tool-node command interpolation**, not agent prompts. `pipeline/handlers/prompt.go:23` calls `ExpandVariables` with `toolCommandMode=false`. Agent prompts get every `ctx` key interpolated unsanitized.

Worse, `pipeline/transforms.go:55-82` auto-injects `last_response` (the previous agent's full LLM output) into every **full-fidelity** agent prompt regardless of whether you reference it (the injection is gated by `fidelity == FidelityFull` per `pipeline/handlers/prompt.go:41-43`). On non-full fidelities the value is not auto-prepended, but it still flows via the compaction path: with the default workflow fidelity `summary:medium`, `last_response` is retained in `mediumKeys` and any `${ctx.last_response}` interpolation reads it back **untruncated** (`pipeline/fidelity.go:51-60, 172-193`). Either way, downstream agent prompts can carry upstream LLM output verbatim.

So if `AgentA` produces 5,000 tokens of output (legitimately or as a prompt-injection payload), all 5,000 tokens land verbatim in `AgentB`'s prompt. If `AgentB` has tool access, this is a cross-node prompt-injection vector.

## Safe patterns

### Pattern 1: `tool` node for closing markers and structured output

If a node's job is "emit a final-status line" or "format a JSON record" or "set a context variable": **use a tool, not an agent.** No LLM, no exposure, deterministic output, no injection surface.

```dippin
tool ReportStatus
  label: "Final Status"
  timeout: 5s
  command:
    set -eu
    sprint=$(cat .ai/current_sprint_id.txt 2>/dev/null || printf '?')
    status=$(awk -F '\t' -v id="$sprint" 'NR>1 && $1==id{print $3}' .ai/ledger.tsv)
    case "$status" in
      completed) printf 'sprint %s completed\n' "$sprint" ;;
      failed)    printf 'sprint %s failed (see FailureSummary above)\n' "$sprint" ;;
      *)         printf 'sprint %s status=%s\n' "$sprint" "$status" ;;
    esac
```

### Pattern 2: bare `tool Start` / `tool Exit` passthroughs

The engine has a `passthrough` handler that auto-wires `Start` and `Exit` nodes that lack a real handler. But once you give them a `prompt:` body, they become full coding-agent sessions. So:

```dippin
# GOOD — passthrough tool
tool Start
  label: Start
  timeout: 5s
  command:
    printf 'pipeline-start\n'

tool Exit
  label: Exit
  timeout: 5s
  command:
    printf 'pipeline-complete\n'

# ALSO GOOD — engine-recognized bare passthrough
agent Start
  label: Start

agent Exit
  label: Exit

# BAD — the v0.28.2 anti-pattern
agent Exit
  label: Exit
  prompt:
    Report the final status. HARD CONSTRAINT: do not write files.
    # The HARD CONSTRAINT will NOT prevent the agent from writing
    # files. Once it has tool access, it can use the tools regardless
    # of what you tell it in the prompt.
```

### Pattern 3: `backend: claude-code` for agents that need to run unprivileged

For nodes that genuinely need an LLM but should NOT have file-system access, route through the claude-code backend with an explicit disallow list:

```dippin
agent SummarizeRun
  backend: claude-code
  disallowed_tools: "Write,Edit,Bash,Read,Grep,Glob,WebFetch"
  max_turns: 1
  prompt:
    Summarize the run in one paragraph based on ${ctx.last_response}.
```

The claude-code backend honors `disallowed_tools` (`pipeline/handlers/backend_claudecode.go:242-243`) AND strips API key env vars from the subprocess. Still bound `max_turns` aggressively to prevent multi-turn drift.

### Pattern 4: reuse existing upstream output instead of re-summarizing

If an upstream node (e.g. `FailureSummary`, `ReviewAnalysis`) is already an LLM that produces a narrative, don't stack another agent downstream to re-summarize it. The original output is already in the run artifacts and in `ctx.last_response` for any consumer that needs it.

## Lint codes that catch a subset of these

- **DIP110**: empty `prompt:` on an agent (good — passthrough form)
- **DIP111**: missing `timeout:` on a tool — *add timeouts*
- **DIP125**: tool command binary not on PATH (validator-time hint)
- **DIP104**: unbounded retry loop (`max_restarts:` missing or `retry_target` cycles)

These do NOT catch the safety issues above — there's no lint for "agent at terminal node has prompt body" or "this node has tool access without `backend: claude-code`."

## Anti-pattern audit checklist

When reviewing or authoring a `.dip` file, scan for:

1. `agent <Start|Exit|Done>` with a `prompt:` block — convert to `tool` or bare-agent passthrough.
2. Any agent node that says "do not write files" in its prompt — that's an admission that it has tool access it shouldn't. Move to `backend: claude-code` + `disallowed_tools`, or replace with a tool node.
3. Two-agent chains where downstream uses `${ctx.last_response}` AND has tool access — verify the upstream output is trusted.
4. `max_turns:` missing or > 30 on an agent — set explicitly per node based on actual work.
5. Tool nodes routing on `ctx.tool_stdout` substring (TRK101) — use `marker_grep:` or `_TRACKER_ROUTE=` sentinel.

## See also

- [tracker CLAUDE.md](https://github.com/2389-research/tracker) — engine-level gotchas.
- [dippin-lang validator/lint_codes.go](https://github.com/2389-research/dippin-lang) — the authoritative DIP code reference.
- The v0.28.2 fix that aligned built-in workflows with `ensureStartExitNodes`' passthrough-only-when-no-prompt contract. The helper itself predates v0.28.2 (introduced with the Dippin IR adapter, refined for non-codergen handlers via tracker issue #69); v0.28.2 fixed the *misuse* where built-in workflows tripped the prompt-skip path and unintentionally ran as full coding-agent sessions.
