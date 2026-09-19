# tracker-claw

A request/action/reply loop expressed in DIP. Give it a task,
review its proposed scope, approve it, and inspect the result. The session
remembers completed work and decisions for your next request.

tracker-claw uses Tracker's terminal interface and checkpoints. Messaging
gateways, heartbeats, scheduling, and plugins are outside its scope.

## Run

Requires Tracker **0.73.1+** and provider credentials (`tracker setup`). The
workflow uses the native backend. Dippin **0.72.0** is the tested compiler.
Planning, revision, and memory use `deepseek-4.1-flash`; execution uses `glm-5.3`.
Both use `openai-compat`, matching the repository's Lunaroute-backed kata
workers. Configure `OPENAI_COMPAT_API_KEY` and `OPENAI_COMPAT_BASE_URL` with
Tracker. Model selection lives in the workflow defaults and Execute's model
override. Tracker 0.73.1 does not expand model/provider parameters for top-level
agents.

From the pipelines checkout, point Tracker at the directory where the agent
should work:

```sh
tracker --no-tui -w /absolute/path/to/workspace tracker-claw/agent.dip
```

Use a workspace whose files you intend the agent to access. Planning has no
tools; if a task needs inspection first, approve a discovery task, review the
findings, then approve implementation.

## Conversation

1. **Request:** enter a task as one line. Include targets, constraints, and how
   the agent should prove it worked.
2. **Proposal:** inspect the goal, allowed actions, exclusions, and checks.
   Choose **Approve**, **Revise**, or **Stop**. Revision requests produce a
   replacement proposal and return to approval.
3. **Execution:** the agent performs the approved task, checks its work, and
   reports evidence, partial work, and anything still blocked.
4. **Review:** choose **Next task** to continue with session memory, or **Stop**.
   Follow-up work gets its own proposal and approval.

For example, request “Inspect the failing parser test and propose a fix;
do not edit files.” After reviewing the findings, request “Implement that fix
in the parser and run its tests; do not commit or push.”

In `--no-tui` mode, type the choice text or its number. Blank input or closed
stdin at a choice gate selects **Stop**. A freeform request or revision must
contain text. An invalid choice fails at the gate and leaves a checkpoint.

Only Execute has tools. The other agents cannot inspect or change files.
Approval authorizes a bounded task, **not each individual tool call**. Once
Execute starts, scope is enforced by its instructions; this DIP is not a
per-command authorization system or filesystem sandbox. Use an isolated
workspace and appropriate credentials for the tasks you approve.

Do not use `--autopilot` or `--auto-approve` for an interactive session: those
replace human input. Stop is deliberately the default and first choice.

## State and recovery

Tracker keeps the checkpoint and node artifacts under
`WORKSPACE/.tracker/runs/RUN_ID/`. The memory agent summarizes the previous
memory plus the latest result. It retains facts and outstanding work, rather
than replaying an ever-growing transcript. Inspect the latest node artifacts
and the run's activity log for details; repeated nodes overwrite their earlier
per-node files. Starting a new run starts a new session.

Resume the same workflow and workspace using the saved run ID:

```sh
tracker --no-tui -w /absolute/path/to/workspace \
  --resume RUN_ID tracker-claw/agent.dip
```

A checkpoint at Approval reopens that gate with its proposal. Do not blindly
resume a checkpoint at Execute: an interrupted tool call may already have
changed files or an external system, and resuming may run it again. Inspect
the artifacts and actual state first. If needed, start a new session with a
task that reconciles the partial work.

There are no automatic execution retries. A reported task failure returns its
partial result for review; another attempt needs a new request and approval.
Choosing Stop after a failed task leaves the run failed (nonzero exit), even
though the review itself completed. Choosing Next task starts a fresh approved
task. A missing execution status also counts as failure.
Some provider errors, authentication failures, or billing limits stop or pause
Tracker directly. Resolve the provider problem and inspect the checkpoint
before deciding whether to resume. The workflow does not claim success for
unfinished task work merely because the conversation ended cleanly.

Execution is capped at 80 model turns; planning at 8 and memory at 6. Each loop
target allows 40 restarts. Memory is capped by instruction at 500 words. Tracker
also accepts `--max-cost` (cents), `--max-tokens`, and `--max-wall-time`; those
budget checks occur between nodes, so they are not a per-tool spending cap.
Tracker 0.73.1 has no price entry for `deepseek-4.1-flash`, so `--max-cost`
cannot account for its calls. Use a token limit and wall-time limit for this
configuration; the live test uses 50,000 tokens and 10 minutes per scenario.

## Checks

The offline check validates the graph and exercises real human-gate behavior
without calling a model:

```sh
sh tracker-claw/check
```

Offline checks need no credentials. The gate fixture has no agents; its test
isolates Tracker configuration and supplies an unused client key solely to
satisfy Tracker's startup requirement. No model response is simulated.

The opt-in live check uses real configured providers and incurs model charges.
It creates temporary workspaces and retains logs. It checks rejection, missing
approval, proposal revision, actual file writes, memory on a second task,
approval-gate resume, and task failure without an automatic retry:

```sh
sh tracker-claw/tests/live.sh
```

Prerequisites for checks: `tracker`, `dippin`, `jq`, and `shellcheck`. No mocked
model is used by the live test.
