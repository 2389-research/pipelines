# OpenClaw Human Gates Implementation Plan

> **For agentic workers:** Use subagent-driven-development to implement the
> workflow task, then review the whole change. Doctor Biz already prefers
> delegated implementation and approved bounded-task gates.

**Goal:** A usable DIP conversation agent that executes one human-approved task
at a time and retains session memory.

**Architecture:** Tool-free planning and memory nodes surround one tool-enabled
executor. Tracker owns checkpoints, input, routing, and response persistence.

**Tech Stack:** DIP, POSIX shell, jq, Tracker 0.73.1, Dippin 0.72.0.

## Global constraints

- Work only in `/Users/harper/Public/src/2389/pipelines-openclaw` on
  `feat/openclaw-human-gates`; preserve the original checkout.
- User chose approval of each bounded task, not each tool invocation.
- Stop is first and default at choice gates; freeform gates have no default.
- Only Execute has tools. No automatic execution retry (`retry_policy: none`).
- Use existing runtime state; no separate state database or daemon.
- Test real runtime behavior; no mocked end-to-end agents or production mock mode.
- Document that task scope after approval is prompt-enforced.

## Task 1: Workflow and deterministic checks

Files: create `openclaw/agent.dip`, `openclaw/check`, and focused shell tests
under `openclaw/tests/`. These paths are owned by the implementation agent.

Interfaces: `tracker --no-tui -w TARGET openclaw/agent.dip` starts the session.
`sh openclaw/check` runs offline checks with dippin, tracker, jq, and shellcheck.
No tests contact a configured target repository.

- [ ] Write tests that fail because the workflow is missing. Check actual parsed
  graph reachability so Execute can only be entered through Approval's explicit
  Approve choice. Check safe defaults, tool catalog bounds, and retry policy.
- [ ] Implement Start → Request → Propose → Approval → Execute → Remember →
  Review, with Approval → Feedback → RevisePlan → Approval and human Stop/Next
  choices. Plan failures return a problem gate. Use explicit failure edges.
- [ ] Use `${ctx.response.Request}` for the request, `${ctx.last_response}` for
  the current proposal across Approval/Feedback, and `${ctx.response.Remember}`
  for prior memory. Do not declare synthetic writes requiring JSON extraction.
- [ ] Add real-runtime gate tests covering stop, invalid/missing input, and
  resume. Test helper fixtures must not pretend to be real agent end-to-end tests.
- [ ] Run `sh openclaw/check`; require no new warnings. Record red and green
  commands/results in an implementation report, review files, then commit.

## Task 2: Live use, documentation, and integration

Files: `openclaw/tests/live.sh`, `openclaw/README.md`, `.github/workflows/openclaw_check.yml`,
root `README.md`, `CHANGELOG.md`, `gotchas.md`. Owned by the parent agent.

- [ ] Add an opt-in real-provider smoke script using isolated temporary workdirs.
  Drive gates through a persistent stdin pipe or pseudo-terminal (piped multiple
  lines can be swallowed by gate readers); verify actual filesystem effects.
- [ ] Run an approved harmless file task, revision, a second task recalling the
  first, rejection without execution, and resume at a waiting gate. Capture logs
  without exposing credentials. Fix any defects with regression coverage.
- [ ] Document launch and resume commands, stop/revise/approve behavior, bounded
  memory and turn budgets, provider setup, and partial-effect recovery.
- [ ] Add CI for `sh openclaw/check`, pinning existing toolchain versions.
- [ ] Run the canonical new check plus repository-wide `dippin check`, review
  the full diff, address findings, and commit. Keep the branch/worktree for
  Doctor Biz; do not merge.

## Progress

- Baseline: all 60 existing DIP files pass `dippin check`.
- Design approved: bounded-task approval (A).
- Compactions: 0.
