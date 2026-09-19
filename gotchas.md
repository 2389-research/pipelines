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
using `openai-compat`: `deepseek-4.1-flash` for worker/repair/correctness and
`glm-5.3` for scope. After post-claim authentication failures, resume
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

Doctor Biz wants a fresh branch for every claimed kata, cut from the checked-out
local trunk. After both reviewers approve the same SHA, the close step lands it
on trunk, closes the kata, returns to trunk, and deletes the task branch. The
pipeline makes no remote Git or GitHub calls; the operator decides when to push.

Doctor Biz chose local trunk landing for whole-board runs. Each approved child
fast-forwards trunk, so the next child starts from the landed commit; failed
workers and unlanded task branches return to trunk and do not become a base. A
close failure after the ref update leaves the approved commit on trunk. Tracker 0.73.1 native
subgraphs share run identity/artifacts, so board.dip calls separate complete.dip
CLI runs and records their IDs. Resume resolves the current child before another
claim. No ready work with open items remaining means incomplete.

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
child hands its kata off (label, comment, WIP commit, trunk restored)
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

## Conversational task gates (decided 2026-09-19)

Doctor Biz chose approval per bounded task for `tracker-claw/agent.dip`. Planning
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

Doctor Biz named this agent `tracker-claw`; use that name in workflow paths,
documentation, and new references. Historical test logs retain their original paths.

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

The trigger is a literal `.` anywhere inside the braces, and shell parameter
defaults are not exempt (measured through real tracker 2026-09-19). `${VAR:-a.b}`,
`${VAR:-$w/.tracker/x}`, and `${VAR:-$(cat "$w/.tracker/f" 2>/dev/null || echo unk)}`
all blank to empty — and blank **even when VAR is set**, because the expander
rewrites the text before `/bin/sh` applies the `:-`. Command substitution,
redirects, and `||` are innocent: `${VAR:-$(cd "$w" && pwd -P)}` survives because
its default holds no dot. `claim-next.sh` and `handoff-selected.sh` hit this
reading `.tracker/kata-board-run-id` for a run-id fallback, so a claimed kata's
run id came out empty under the board.sh fixture (which inlines the handoff
script via `command_file`). Fix: read the dotted value into a plain variable
first — `x=$(cat "$w/.tracker/f" ...)` — then fall back with `${VAR:-$x}`, whose
default is dot-free.

## Run Kata from the local trunk that should receive the work (decided 2026-09-19)

`kata/scripts/claim-next.sh` records the checked-out branch as `trunk`, refuses
detached HEAD and `kata/*`, and cuts the task branch from the local tip. Close
accepts trunk movement only when the new tip is still an ancestor of the
reviewed head; an already-landed retry is valid, while divergence needs a rebase
and both reviews again. Legacy selected state without `trunk` stops for manual
inspection. The pipeline never fetches or checks a remote base.

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
input received` (`.error` contains that text on `gate_resolved`; `.gate_response`
is null). Either failure saves a checkpoint, and `tracker -r` reopens the gate.
`--auto-approve` picks the default, else the first choice; `kata/board.dip` sets
no default, so its unattended answer is the first choice, `Done`, and Escape in
the terminal modal picks the same. Under `--json --no-tui` the prompt still
prints among the event lines, and `gate_resolved` shares the `Enter choice` line
(no newline), so strip everything before the first `{` before `fromjson`.
`max_restarts` is accepted only inside a `defaults` block; at workflow level
dippin 0.72.0 and tracker 0.73.1 fail to parse ("unexpected top-level
identifier").

## Guard controller command substitutions under `set -e` (verified 2026-09-19)

A bare `value=$(kata ...)` exits `kata/scripts/run-board.sh` immediately when
Kata fails, before the ledger stop helpers can save `stop_reason` and print
`board-needs-human`. Route list failures through `stop_board` and child-specific
show failures through `stop_for_inspection`; validating successful JSON does not
cover a nonzero CLI exit.

The close path has the same rule for Git reads: capture and check `git status`
and `git worktree list` exit codes before interpreting their output. Empty output
after a failed command does not prove a clean tree or an unused trunk.
