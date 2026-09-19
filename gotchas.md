# Pipeline notes

For the kata pipeline, Doctor Biz chose next ready, unowned selection,
exactly one item per run. Planning stays within that item. Reviews emulate
fresh-eyes checks with two different models and distinct expert roles.

Never create practice issues to probe kata. Inspect CLI help, source, or
existing records read-only. Isolate test state from the real daemon.

Kata runs may start on main in a repository without tracker ignore rules.
Prepare local artifact exclusions and a task branch automatically; preserve
unrelated uncommitted work and report its paths. Keep preflight failures on
ClaimNext rather than masking them with a generic Stop node.

Doctor Biz wants kata agents routed through the configured Lunaroute gateway
using `openai-compat`: `glm-5.3` for worker/repair/correctness and
`deepseek-4.1-flash` for scope. After post-claim authentication failures, resume
the saved run with the same pipeline to preserve its claim; do not start over.

Doctor Biz wants much larger kata turn ceilings so checks, evidence, and
commits can finish: implementation 300, repair 150, each review 100. Bound
discovery to relevant code; do not narrow the selected item's goal to fit a cap.

Tracker resume continues at the saved node, including a terminal Handoff. An
implementation turn-limit breach with steady progress gets one automatic warm
continue inside the pipeline (ContinueImplement); a second breach hands the kata
off for the morning review, so there is no manual rewind command. Check the
repository-local checkpoint: tracker v0.73.1 can write fresh logs under
~/.local/state/tracker while leaving a stale checkpoint copy there.

Live recovery and completion passed for todo-test#tzrg on 2026-09-13: both
model reviews approved commit 510d313, closure succeeded, and the tree was clean.

Kata ready/next may return parent epics with open children: parent links do
not count as blocking predecessors. Filter ready results by child_counts.open
before claiming. Preserve explicit priority order (unset last, received order
for ties), and never try another claim after losing an ownership race.

Doctor Biz wants a fresh branch for every claimed kata and a PR when GitHub
is configured. GitHub tasks start from the fetched default branch; local-only
tasks start from current HEAD. Publish only the SHA approved by both reviewers,
reuse a matching open PR, and leave the kata open if publication fails.

Doctor Biz chose stacked branches and PRs for whole-board runs, leaving merging
to the operator. Each kata uses the previous approved task as its base. Tracker
0.73.1 native subgraphs share run identity/artifacts, so board.dip calls separate
complete.dip CLI runs and records their IDs. Resume resolves the current child
before another claim. No ready work with open items remaining means incomplete.

Tracker 0.73.1 treats any TUI exit as a run cancel. Pressing `q` or Ctrl-C in
the TUI cancels the pipeline context, SIGKILLs the running tool's process group
(for board.dip: the controller and its child tracker), and reports the failure
as `command timed out after <node timeout>` because translateExecError labels
every ctx.Err() a timeout. Run board.dip with `--no-tui`. A killed child keeps
its kata claim, so resume the child before the board. Verified 2026-09-15 under
tmux with a sleeping nested child: `q` and Ctrl-C both reproduced the exact
board failure; the same runs left alone completed with the TUI on or off.

kata scripts resolve every path physically (`pwd -P`), so a test that compares
a path against script output must resolve its own path the same way. On this
machine `~/workspace` is a symlink to `~/Public/src`, and the agent shell's cwd
is the symlinked form: a kata test once computed its pipeline_dir with logical
`pwd`, grepped that path in a script's output, missed, and `set -e` exited 1
with no message, so `kata/check` went red silently. The same test passed when
invoked by its physical path. Fixed with `pwd -P` on 2026-09-15.

Doctor Biz chose fail-forward boards with a morning review (2026-09-16): a failed
child hands its kata off (label, comment, WIP commit, starting branch restored)
and the board claims the next one; three consecutive failures stop it. A queue
with only owned or blocked katas finishes the board. `kata/board-report`
summarizes a board run and `kata/answer` comments a reply and releases the
pipeline claim. Implement gets one automatic warm continue (450 turns) after a
steady turn-limit breach; the second breach hands off.

## Conversational task gates (decided 2026-09-19)

Doctor Biz chose approval per bounded task for `openclaw/agent.dip`. Planning
and memory have no tools; only an approved executor does. Scope inside that
execution is prompt-enforced, not per-tool authorization. Tracker 0.73.1 drops
`max_retries: 0` during DIP adaptation: use `retry_policy: none` to disable
automatic task retries. Resume at a human gate preserves its proposal; resume
at an interrupted executor can repeat partial effects, so inspect first.
Use direct prompt references to built-in response keys with `fidelity: full`:
Dippin 0.72.0 does not recognize their automatic writes in `reads:` declarations.
The configured Anthropic endpoint rejected its key during live validation;
the existing Lunaroute `openai-compat` configuration passed real probes.
Planning/memory use `deepseek-4.1-flash` and execution uses `glm-5.3`.
Execute must be a goal gate: Tracker otherwise treats a missing STATUS line
as success. Stop after task failure returns nonzero; Next task clears that
gate through the Request restart. Review overrides cannot cover Execute
through Remember: Tracker's override matching does not follow multiple hops.
Tracker 0.73.1 lacks a Deepseek Flash price entry; dollar caps omit that usage.
The live smoke test uses token and wall-time limits instead.
Tracker also constructs a native client for graphs containing no agents. Offline
gate fixtures must isolate config and bootstrap an unused client; an empty
config otherwise fails before reaching any gate. Assert the fixture has no
agent nodes, and leave real-provider end-to-end checks separate.
