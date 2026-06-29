# Agent-node safety in `.dip` pipelines

> Verified against `tracker v0.29.2` / `dippin v0.27.0` engine source by three independent reviewers, 2026-05-18. The findings below shape what's safe and what's a foot-gun when designing `agent` nodes for the workflows in this repo.

> **Update — dippin v0.32.0:** This doc was written at v0.27.0, when there was no language-level primitive to bound agent tool access. [dippin-lang#41](https://github.com/2389-research/dippin-lang/issues/41) closed that gap in v0.32.0 with the `tool_access: none` agent-node field, which strips the model's tool catalog at the language level. The TL;DR below has been updated to reflect this; the deeper analysis sections still describe the pre-v0.32.0 runtime accurately and remain useful for understanding *why* the bounds matter. A broader rewrite is tracked in [#20](https://github.com/2389-research/pipelines/issues/20).

## TL;DR

On the **native backend** (the default), `agent` nodes have full read/write/bash/edit/glob/grep tool access **unless** the node declares `tool_access: none` (dippin ≥ v0.32.0). For workflows pinned to older trackers/dippin, the catalog cannot be suppressed structurally and you must rely on the prompt-level mitigations below.

Conventions for safe agent design:

1. **`Start` and `Exit` should always declare `tool_access: none` + `max_turns: 1`** (or, on toolchains pinned to dippin < v0.32.0, prefer `tool` nodes / bare `agent` with no prompt) — the v0.28.2 runaway-agent bug came from acknowledge-only agents shipping the full tool catalog.
2. **For any "summarize / format the output / write a closing message" need: prefer a `tool` node** templating from safe `ctx.*` keys and disk files. Zero LLM, zero exposure.
3. **If you genuinely need an LLM at a node that should not touch files**, declare `tool_access: none`. On older toolchains, `backend: claude-code` with explicit `disallowed_tools` is the fallback — the native backend silently drops those attributes.
4. **Don't trust `${ctx.last_response}` content** when designing downstream agent prompts — it's a cross-node prompt-injection vector. `tool_access: none` bounds the catalog but does not sanitize incoming context strings.

## Structural bound tiers

(Per-tier minimum versions are noted on each bullet — `tool_access: none` lands
in dippin v0.32.0, `writable_paths:` in v0.35.0.)

The v0.28.2 runaway-agent vector documented in the analysis below was
**prompt-only** when this doc was written at v0.27.0. It is now structurally
bounded **on a runtime that enforces these fields** — the top-level `tool_access`
form requires tracker ≥ v0.39.0 (this repo's floor; on v0.31–v0.38 it parses but
silently no-ops at runtime — [tracker#366](https://github.com/2389-research/tracker/issues/366),
see [the migration note](migrations/0.32-tool-access-none.md#compatibility)). Two
language-level fields exist, and they are not interchangeable —
pick the tightest tier that still lets the node do its job:

- **`tool_access: none` (v0.32.0)** — strips the *entire* tool catalog
  (`Read` included). Use for acknowledge-only `Start`/`Exit` agents and for LLM
  nodes that reason over context but must never touch the filesystem. It is
  all-or-nothing on the native backend; do not apply it to a node that needs its
  native `Read` tool (see the read-bounded waiver below).
- **`writable_paths:` (v0.35.0)** — keeps the catalog but confines writes to the
  listed path globs (a filesystem jail). Use for agents that legitimately read
  broadly and implement, but should only *write* inside a known scope — e.g.
  `writable_paths: .dev_loop_worktree/**` on the `dev_loop` implementer,
  `writable_paths: workspace/.review-failed` on greenfield review.
  Enforcement is **Linux-only** (Landlock + openat2); on macOS/Windows tracker
  refuses to start when the field is set, and older tracker releases reject it as
  an unknown field. Full-chain symlinks are rejected.

Supporting lints (advisory — they do not by themselves bound anything):

- **DIP140 (v0.35)** — flags a params-based bypass of the `writable_paths` jail
  (a path scope that an interpolated param could escape).
- **DIP143 (v0.36)** — subgraph-containment advisory: a subgraph's nodes should
  stay within its declared boundary. See
  [`dip143-subgraph-audit.md`](dip143-subgraph-audit.md).

Tier-selection rule of thumb: no filesystem need → `tool_access: none`; scoped
write need → `writable_paths:`; unscoped read need with write-bounding prose →
read-bounded waiver (below). Version-by-version detail is in
[`migrations/0.32-to-current.md`](migrations/0.32-to-current.md).

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

## Read-bounded agents: why `tool_access: none` does NOT apply (issue #110)

[Issue #110](https://github.com/2389-research/pipelines/issues/110) flagged 10 agent
nodes as "pure read-only reporters guarded by prose" and proposed adding
`tool_access: none`. On audit, all 10 are **Category C — read-bounded**: their job is
to *read* one or more files (via the agent's native `Read` tool) and report on them.
Their `HARD CONSTRAINT` / `Do NOT modify any files` prose bounds **writes**, not tool
access in general — the agent legitimately needs read access to function.

`tool_access: none` is **all-or-nothing on the native backend** (it strips the entire
tool catalog, including `Read` — see "The native backend always ships the full tool
catalog" above). Applying it to a read-bounded node would remove the very `Read` tool
the node needs, breaking it. The native backend has no working scoped-allowlist
primitive (`allowed_tools` / `disallowed_tools` are silently dropped on the native
backend — see "The native backend always ships the full tool catalog" above),
and the `backend: claude-code` fallback (Pattern 3) is incompatible here because these
nodes are pinned to specific providers/models (e.g. `gemini-3-flash-preview`,
`claude-opus-4-7`) that the claude-code backend cannot honor.

So these 10 sites are **intentionally waived** from the `tool_access: none` sweep and
carry an inline `# CAT-C READ-BOUNDED (issue #110)` marker so future audits recognize
them as reviewed exceptions rather than missed instances. This matches the
[`tool_access: none` sweep plan](superpowers/plans/2026-05-27-tool-access-none-sweep.md)'s
own "Category C" exclusion ("agents that legitimately read files ... keep as-is").

| File | Agent | Reads |
|---|---|---|
| `iterative/iter_dev.dip` | `already_complete_exit` | `docs/iterations/final-progress.md`, `docs/iterations/roadmap.md` |
| `sprint/sprint_exec-cheap.dip` | `FindNextSprint` | `.ai/ledger.tsv` |
| `sprint/sprint_exec-cheap.dip` | `ReadSprint` | `.ai/current_sprint_id.txt`, `.ai/sprints/SPRINT-<id>.md` |
| `sprint/sprint_exec.dip` | `FindNextSprint` | `.ai/ledger.tsv` |
| `sprint/sprint_exec.dip` | `ReadSprint` | `.ai/current_sprint_id.txt`, `.ai/sprints/SPRINT-<id>.md` |
| `sprint/sprint_exec_yaml.dip` | `ReadSprint` | SPRINT-<id>.yaml + .md |
| `sprint/sprint_exec_yaml_v2.dip` | `ReadSprint` | SPRINT-<id>.yaml + .md |
| `sprint/sprint_runner_yaml.dip` | `deps_blocked_exit` | `.ai/ledger.yaml` |
| `sprint/sprint_runner_yaml_v2.dip` | `deps_blocked_exit` | `.ai/ledger.yaml` |
| `sprint/verify_sprint.dip` | `SemanticReview` | SPRINT-<id>.yaml + .md + source files |

The lasting remediation for the prompt-vs-language gap on read-bounded nodes lives
upstream: a scoped read-only tool primitive on the native backend (tracked in
dippin-lang). Until that exists, prose remains the only available bound for these
nodes, and the marker comments make the audit decision explicit and re-checkable.

## See also

- [tracker CLAUDE.md](https://github.com/2389-research/tracker) — engine-level gotchas.
- [dippin-lang validator/lint_codes.go](https://github.com/2389-research/dippin-lang) — the authoritative DIP code reference.
- The v0.28.2 fix that aligned built-in workflows with `ensureStartExitNodes`' passthrough-only-when-no-prompt contract. The helper itself predates v0.28.2 (introduced with the Dippin IR adapter, refined for non-codergen handlers via tracker issue #69); v0.28.2 fixed the *misuse* where built-in workflows tripped the prompt-skip path and unintentionally ran as full coding-agent sessions.
