# tracker-claw Human Gates Implementation Plan

> **For agentic workers:** Use subagent-driven-development to implement the
> workflow task, then review the whole change. Doctor Biz already prefers
> delegated implementation and approved bounded-task gates.

**Goal:** A usable DIP conversation agent that executes one human-approved task
at a time and retains session memory.

**Architecture:** Tool-free planning and memory nodes surround one tool-enabled
executor. Tracker owns checkpoints, input, routing, and response persistence.

**Tech Stack:** DIP, POSIX shell, jq, Tracker 0.73.1, Dippin 0.72.0.

## Global constraints

- Work only in `/Users/harper/Public/src/2389/pipelines-tracker-claw` on
  `feat/tracker-claw-human-gates`; preserve the original checkout.
- User chose approval of each bounded task, not each tool invocation.
- Stop is first and default at choice gates; freeform gates have no default.
- Only Execute has tools. No automatic execution retry (`retry_policy: none`).
- Use existing runtime state; no separate state database or daemon.
- Test real runtime behavior; no mocked end-to-end agents or production mock mode.
- Document that task scope after approval is prompt-enforced.

## Task 1: Workflow and deterministic checks

Files: create `tracker-claw/agent.dip`, `tracker-claw/check`, and focused shell tests
under `tracker-claw/tests/`. These paths are owned by the implementation agent.

Interfaces: `tracker --no-tui -w TARGET tracker-claw/agent.dip` starts the session.
`sh tracker-claw/check` runs offline checks with dippin, tracker, jq, and shellcheck.
No tests contact a configured target repository.

- [x] Write tests that fail because the workflow is missing. Check actual parsed
  graph reachability so Execute can only be entered through Approval's explicit
  Approve choice. Check safe defaults, tool catalog bounds, and retry policy.
- [x] Implement Start → Request → Propose → Approval → Execute → Remember →
  Review, with Approval → Feedback → RevisePlan → Approval and human Stop/Next
  choices. Plan failures return a problem gate. Use explicit failure edges.
- [x] Use `${ctx.response.Request}` for the request, `${ctx.last_response}` for
  the current proposal across Approval/Feedback, and `${ctx.response.Remember}`
  for prior memory. Do not declare synthetic writes requiring JSON extraction.
- [x] Add real-runtime gate tests covering stop, invalid/missing input, and
  resume. Test helper fixtures must not pretend to be real agent end-to-end tests.
- [x] Run `sh tracker-claw/check`; require no new warnings. Record red and green
  commands/results in an implementation report, review files, then commit.

## Task 2: Live use, documentation, and integration

Files: `tracker-claw/tests/live.sh`, `tracker-claw/README.md`, `.github/workflows/tracker_claw_check.yml`,
root `README.md`, `CHANGELOG.md`, `gotchas.md`. Owned by the parent agent.

- [x] Add an opt-in real-provider smoke script using isolated temporary workdirs.
  Drive gates through stdin; Tracker 0.73.1 uses a shared scanner, so piped
  multiple lines survive between gates. Verify actual filesystem effects.
- [x] Run an approved harmless file task, revision, a second task recalling the
  first, rejection without execution, and resume at a waiting gate. Capture logs
  without exposing credentials. Fix any defects with regression coverage.
- [x] Document launch and resume commands, stop/revise/approve behavior, bounded
  memory and turn budgets, provider setup, and partial-effect recovery.
- [x] Add CI for `sh tracker-claw/check`, pinning existing toolchain versions.
- [x] Run the canonical new check plus repository-wide `dippin check`, review
  the full diff, address findings, and commit. Keep the branch/worktree for
  Doctor Biz; do not merge.

## Progress

- Baseline: all 60 existing DIP files pass `dippin check`.
- Design approved: bounded-task approval (A).
- Compactions: 0.
- Task 1: committed in `d44923c`, review fixes in `6649255`. Both P2 findings
  closed by independent re-review; spec and quality pass.
- Task 2: complete. Offline check (including empty XDG configuration), shellcheck,
  actionlint, all 62 DIP checks, and the real-provider suite passed. Independent
  review and fresh-eyes review found no remaining blocking defects.

## Final verification evidence

The live suite (then `sh openclaw/tests/live.sh`) passed on 2026-09-19 with Tracker 0.73.1 and the
final workflow. It used real Lunaroute providers and temporary workspaces.
No pricing warnings remain: the harness uses token and wall-time limits.
Logs and artifacts were retained at
`/var/folders/rc/cyjg3p3x0cb4w4xlb8yqm_1h0000gn/T/openclaw-live.hxKDt9`.

| Scenario | Run ID | Result |
|---|---|---|
| Reject proposal | `a23c49da8bc8` | No Execute visit or file write |
| Close approval input | `984c1cab6ef8` | Defaults to Stop; no execution |
| Revise and run two tasks | `d781c111b04e` | Approved filename only; second task recalled session code |
| Resume approval gate | `3db1b818090b` | One planning pass and one execution across resume |
| Missing required input | `a2efc65f6d48` | Failed task reviewed once, stopped nonzero, no retry or invented input |

Review fixes made missing execution verdicts fail closed and kept revised-away
scope out of current memory. A credential-free CI rehearsal found Tracker's
unused-client startup requirement; `faecd25` isolates the offline fixture and
asserts it contains no agents before starting Tracker. No fake model responses
are used. The original checkout still has only its pre-existing changes.

Remaining limits: task scope and memory content are prompt-enforced; execution
resume is not exactly once. Use an isolated target workspace and inspect partial
effects before resuming an interrupted executor. No known code defect remains
that must be fixed before using the documented bounded-task workflow.
