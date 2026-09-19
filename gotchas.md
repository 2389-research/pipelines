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

## Boards fail forward into a morning review (decided 2026-09-16)

Doctor Biz chose fail-forward boards with a morning review (2026-09-16): a failed
child hands its kata off (label, comment, WIP commit, starting branch restored)
and the board claims the next one; three consecutive failures stop the sweep. A
queue with only owned or blocked katas finishes the sweep. Since 2026-09-18
every stop after the ledger exists (three failures, a child needing inspection,
a failed `git status`, an unreadable open-board listing) records `stop_reason`
in `board/state.json` and still ends with `board-needs-human`, so the parent
holds the `Morning review` gate with the reason under the review's header; only
failures before the ledger exists (Tracker variables unset, a missing tool, a
held lock, an untrusted ledger) exit 1 with no marker, and their message is in
`.tracker/runs/<board-run-id>/RunBoard/status.json`. `kata/board-report`
summarizes a board run and `kata/answer` comments a reply and releases the
pipeline claim. Implement gets one automatic warm continue (450 turns) after a
steady turn-limit breach; the second breach hands off.

## Tracker blanks dotted expansions in command_file scripts (verified 2026-09-17)

Tracker inlines a `command_file:` script into the tool command and runs its
variable expander over the text: every `${...}` containing a dot with a
namespace other than ctx, params, graph, or inputs becomes an empty string, so
`${1#https://github.com/}` and `${x%.git}` silently vanish. Verified on tracker
v0.73.1 (2026-09-17): the same script printed empty values via `command_file:`
and correct ones when a node ran `sh "${graph.workflow_dir}/scripts/x.sh"`.
Kata tool nodes run scripts by path; `kata/tests/tool-commands.sh` fails on
any expansion tracker would blank. The kata tests execute scripts with `sh`
directly, so they cannot see this class of bug on their own.

## The kata binding must be on the GitHub base branch (verified 2026-09-17)

`kata init` binds a workspace with a committed `.kata.toml`. In pr mode
`kata/scripts/claim-next.sh` cuts the task branch from origin's default branch,
not local main. If the binding commit is only local, the checkout drops
`.kata.toml`, every later `kata` call fails with "no project bound to this
workspace", and `close-selected.sh` hands an approved commit off instead of
publishing it, one stranded kata per run. claim-next now refuses such a base
before claiming; push the binding commit first.

Related: `kata assign <ref> none` creates an actor literally named `none`.
`kata ready --unowned` then skips the kata and the board report reads
"owned by none". Release it with `kata unassign <ref> --expect-owner none`.

## Tracker prints human gates, not tool output (verified 2026-09-18)

Under `--no-tui` Tracker 0.73.1 never prints a tool node's stdout or stderr, so a
board sweep is silent for hours and `kata/board.dip` used to end without a word.
A `human` node does print: its label, the prompt with `${ctx.tool_stdout}`
rendered as a fenced `## Tool Stdout` block, the choices numbered in edge order
(`1) Done`), and `Enter choice:` (the default in brackets when the gate has one),
which reads the choice number or the choice text from stdin: `1`, `Done`, and
`done` all pick Done, `2` and `Sweep again` pick the sweep, while `sweep` or a
blank line fails the gate with `invalid choice`. Closed stdin fails it with `no
input received` (`.error` holds that text on `gate_resolved`; `.gate_response` is
null). Either failure saves a checkpoint, and `tracker -r` reopens the gate.
`--auto-approve` picks the default, else the first choice; `kata/board.dip` sets
no default, so its unattended answer is the first choice, `Done`, and Escape in
the terminal modal picks the same. Under `--json --no-tui` the prompt still
prints among the event lines, and `gate_resolved` shares the `Enter choice` line
(no newline), so strip everything before the first `{` before `fromjson`.
`max_restarts` is accepted only inside a `defaults` block; at workflow level
dippin 0.72.0 and tracker 0.73.1 fail to parse ("unexpected top-level
identifier").
