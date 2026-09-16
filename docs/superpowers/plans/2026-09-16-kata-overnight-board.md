# Kata Overnight Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `kata/board.dip` work through a whole board overnight, leave every unfinished kata open and reviewable, and give a person one report and one answer command for the morning.

**Architecture:** `complete.dip` gains one automatic warm continue after a steady-progress turn-limit breach, and a handoff that labels the kata, comments the branch and question, commits WIP, restores the starting branch, and writes `handoff.json`. `run-board.sh` records clean failures in its ledger and keeps claiming, stopping only for integrity problems or three consecutive failures. Two new executables, `kata/board-report` and `kata/answer`, are the morning interface; the kata tracker itself is the inbox.

**Tech Stack:** POSIX `sh` with `set -eu`, `jq`, `git`, the `kata` CLI, tracker v0.73.1, Dippin v0.72.0, ShellCheck.

**Spec:** `docs/superpowers/specs/2026-09-16-kata-overnight-board-design.md`

## Global Constraints

- Toolchain floors: tracker **v0.73.1**, Dippin **v0.72.0**, kata **v0.17.2** or newer, `jq`, `git`, ShellCheck. Verify with `tracker --version`, `dippin --version`, `kata --version` before starting.
- Every script is POSIX `sh` with `set -eu`, starts with a shebang and two `# ABOUTME:` lines, and is ShellCheck clean. New executables (`kata/board-report`, `kata/answer`) have no extension and are `chmod +x`.
- Every path comparison uses `pwd -P`. The agent shell's cwd is a symlinked form of the repository path; a logical `pwd` breaks path assertions silently.
- TDD for every task: write the failing test, watch it fail, implement, watch it pass, commit. The canonical check is `./kata/check`; run it in full before the final commit of each task.
- Tests never contact a real kata daemon or model provider. Every test puts a fixture `kata` on `PATH` and works in a disposable Git repository under `mktemp -d`. Never create practice issues in a real workspace. Do not touch the `mux` or `todo-test-2` workspaces or their kata state.
- Only the pipelines repository changes. Tracker and kata bugs are flagged in the final report, never patched here.
- Never bypass hooks: `--no-verify`, `--no-hooks`, and `--no-pre-commit-hook` are forbidden. Read hook failures and fix the cause.
- Run `git status` before every `git add`; never `git add -A` in this repository. (The handoff script may `git add -A` inside the target repository; that is the product, not this repo.)
- Turn override rule: tracker honors `<workdir>/.tracker/turn_overrides/<node>` only when it is a regular file whose trimmed integer exceeds the node's `max_turns` and is at most 1000. `Implement` has `max_turns: 300`; the continue writes `450`.
- Conventional commits, imperative, present tense: `feat(kata): ...`, `test(kata): ...`, `docs(kata): ...`.
- Never print `~/.config/tracker/.env` values.

## Facts the plan relies on

All verified against tracker v0.73.1 source (`/Users/harper/Public/src/2389/tracker`), Dippin v0.72.0, and kata v0.17.2 `--help` output. Do not re-derive them; do not contradict them.

- Edge selection: tracker picks the first matching **conditional** edge in declaration order; unconditional edges are fallbacks. So `Implement -> ContinueImplement when ctx.turn_breach_class = operator_decision` must be declared before `Implement -> Handoff when ctx.outcome = fail`.
- A failed node whose only outgoing edges are unconditional stops the pipeline as `pipeline_failed`. `Handoff` exits 1 and has only `Handoff -> Exit`, so a handed-off run ends as `pipeline_failed` with the `Handoff/status.json` written. The board reads the activity log's last `pipeline_*` event to tell `pipeline_completed` (terminal_status `success`) from `pipeline_failed`.
- `restart: true` on an edge makes tracker clear the target node's and its downstream nodes' completion and retry state and re-enter the target. Default `max_restarts` is 5 and lives under a `defaults` block; do not add one.
- A tool node's `ctx.outcome` is `success` when its command exits 0 and `fail` otherwise. Tool stdout is saved at `<run>/<Node>/status.json` under `.context_updates.tool_stdout` (trailing newline trimmed) for successful and failed nodes alike; verified 2026-09-16 on a scratch run whose tool printed `handoff-ok` and exited 1 (and `.tool_marker` when `marker_grep` matched).
- Tracker re-enters a codergen node with its prior episode summaries injected into the prompt (`injectPriorEpisodes` in `pipeline/handlers/codergen.go`), and a steady-progress turn-limit breach sets `turn_breach_class = operator_decision` in the node's context updates.
- `command_file:` paths resolve relative to the `.dip` file's directory; tracker runs the file's text through `sh`, so fixture scripts need no execute bit.
- kata CLI: `kata unassign <issue-ref> --expect-owner <owner> --comment <text>`; `kata label add|rm <issue-ref> <label>`; `kata comment <issue-ref> --body-file <path>`; global flags `--workspace`, `--as`, `--agent`, `--json`. `kata show ... --json` and `kata claim ... --json` omit labels. `kata ready --unowned --limit 0 --json` and `kata list --status open --limit 0 --json` return `.issues[]` with `uid`, `qualified_id`, `status`, `title`, `owner` (string or null), and `labels` (array or null).
- Unverified: whether `kata label rm` fails on a label the issue does not carry. The claim therefore removes only labels present in the ready record.
- Dippin simulate cannot follow the granted-continue restart (scenario outcomes are sticky, so the loop never ends). Routes tests cover the exhausted and no-breach paths; a real-tracker fixture covers the granted restart.

## File map

Create:

- `kata/scripts/continue-implement.sh` — grants one warm continue per run (override file + marker).
- `kata/board-report` — prints the morning review for a board run (text or `--json`).
- `kata/answer` — comments a reply on a kata and releases the pipeline claim.
- `kata/tests/continue.sh` — unit + real-tracker checks for the continue.
- `kata/tests/handoff.sh` — checks for the rewritten handoff script.
- `kata/tests/answer.sh` — checks for `kata/answer`.
- `kata/tests/report.sh` — checks for `kata/board-report`.

Modify:

- `kata/complete.dip` — `ContinueImplement` node and the worker edges.
- `kata/board.dip` — ABOUTME and goal wording.
- `kata/scripts/claim-next.sh` — record `start_branch`, delete a stale override, remove handoff labels.
- `kata/scripts/handoff-selected.sh` — full rewrite (classification, WIP, restore, `handoff.json`).
- `kata/scripts/close-selected.sh` — delete the override after closure.
- `kata/scripts/run-board.sh` — fail-forward ledger, stop rules, report at the end.
- `kata/tests/routes.sh`, `kata/tests/fake-kata.sh`, `kata/tests/check.sh`, `kata/tests/publish.sh`, `kata/tests/board.sh` — cover the changes.
- `kata/prompts/implement.md`, `kata/README.md`, `gotchas.md`, `kata/check` — docs and wiring.

Delete:

- `kata/retry-implementation` and `kata/tests/retry-implementation.sh` — the warm continue replaces the manual rewind.

Task order is fixed by dependencies: the board (Task 7) runs the real handoff script (Task 3) and calls `kata/board-report` (Task 6), and the report prints the path of `kata/answer` (Task 5).

---

### Task 1: One automatic warm continue after a steady turn-limit breach

**Files:**
- Create: `kata/scripts/continue-implement.sh`
- Create: `kata/tests/continue.sh`
- Modify: `kata/complete.dip:106` (insert a node before `tool Handoff`) and `kata/complete.dip:120-121` (worker edges)
- Modify: `kata/tests/routes.sh` (whole file shown below)
- Modify: `kata/check:20-29`

**Interfaces:**
- Consumes: tracker env `TRACKER_RUN_DIR`, `TRACKER_WORKDIR`, `TRACKER_RUN_ID`; `Implement` context update `turn_breach_class`.
- Produces: `scripts/continue-implement.sh` writes `<workdir>/.tracker/turn_overrides/Implement` containing `450` and `<run>/continue-implement.json` `{"attempt":1,"max_turns":450,"run_id":"<id>"}`; prints `continue-ok` (exit 0) the first time and `continue-exhausted` (exit 1) after that. Tasks 2, 3, and 4 delete the override file at claim, handoff, and closure.

- [ ] **Step 1: Write the failing test `kata/tests/continue.sh`**

```sh
#!/bin/sh
# ABOUTME: Checks the one-time warm continue: override file, marker, exhaustion, and the real tracker restart loop.
# ABOUTME: Runs the script directly, then drives a tool-only fixture graph through the actual tracker binary.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
script="$pipeline_dir/scripts/continue-implement.sh"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
command -v tracker >/dev/null
command -v jq >/dev/null

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || cat "$test_root/output" >&2
  exit 1
}

# Unit: the first call grants the continue, the second call is exhausted.
workdir="$test_root/unit"
run_dir="$workdir/.tracker/runs/test"
mkdir -p "$run_dir"
TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$workdir" TRACKER_RUN_ID=test sh "$script" >"$test_root/output" 2>&1 ||
  fail 'first continue call failed'
grep -Fx 'continue-ok' "$test_root/output" >/dev/null || fail 'first continue call did not print continue-ok'
[ "$(cat "$workdir/.tracker/turn_overrides/Implement")" = 450 ] || fail 'override file does not hold 450'
jq -e '.attempt == 1 and .max_turns == 450 and .run_id == "test"' "$run_dir/continue-implement.json" >/dev/null ||
  fail 'continue marker has the wrong shape'
if TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$workdir" TRACKER_RUN_ID=test sh "$script" >"$test_root/output" 2>&1; then
  fail 'second continue call succeeded'
fi
grep -Fx 'continue-exhausted' "$test_root/output" >/dev/null || fail 'second continue call did not print continue-exhausted'
[ "$(cat "$workdir/.tracker/turn_overrides/Implement")" = 450 ] || fail 'second call changed the override'
if (unset TRACKER_RUN_DIR; TRACKER_WORKDIR="$workdir" sh "$script") >"$test_root/output" 2>&1; then
  fail 'missing TRACKER_RUN_DIR was accepted'
fi
printf 'ok - continue grants one override of 450 turns and then reports exhaustion\n'

# Integration: the real tracker restarts Implement after a granted continue and hands off after exhaustion.
workflow="$test_root/workflow"
mkdir -p "$workflow/scripts"
cp "$script" "$workflow/scripts/continue-implement.sh"
cat >"$workflow/continue.dip" <<'DIP'
# ABOUTME: Tool-only stand-in for complete.dip's worker loop: claim, implement, one continue, handoff.
# ABOUTME: Exercises the restart edge through the real tracker without models or kata.
workflow ContinueFixture
  goal: "Restart the worker once after a granted continue."
  start: ClaimNext
  exit: Exit

  tool ClaimNext
    command:
      true

  tool Implement
    command_file: implement.sh

  tool ContinueImplement
    command_file: scripts/continue-implement.sh

  tool Handoff
    command_file: handoff.sh

  tool Exit
    command:
      true

  edges
    ClaimNext -> Implement
    Implement -> Exit  when ctx.outcome = success
    Implement -> ContinueImplement  when ctx.outcome = fail
    ContinueImplement -> Implement  when ctx.outcome = success  restart: true
    ContinueImplement -> Handoff  when ctx.outcome = fail
    Handoff -> Exit
DIP
cat >"$workflow/implement.sh" <<'SH'
#!/bin/sh
# ABOUTME: Fails until the visit count reaches the configured success point.
# ABOUTME: Records each visit so the test can count worker restarts.
set -eu
fixture="$TRACKER_WORKDIR/.tracker/continue-fixture"
printf '%s\n' "$TRACKER_RUN_ID" >>"$fixture/visits"
visits=$(wc -l <"$fixture/visits" | tr -d ' ')
[ "$visits" -ge "$(cat "$fixture/succeed-at")" ]
SH
cat >"$workflow/handoff.sh" <<'SH'
#!/bin/sh
# ABOUTME: Stand-in handoff that reports and fails like the real one.
# ABOUTME: Keeps the fixture graph's failure route observable.
printf 'handoff-ok\n'
exit 1
SH

run_fixture() {
  workdir="$test_root/$1"
  git init -q -b main "$workdir"
  mkdir -p "$workdir/.tracker/continue-fixture"
  printf '%s\n' "$2" >"$workdir/.tracker/continue-fixture/succeed-at"
  status=0
  (cd "$workdir" && tracker --git off --workdir "$workdir" --json --no-tui "$workflow/continue.dip") \
    >"$test_root/output" 2>&1 || status=$?
  run_id=$(jq -Rr 'fromjson? | select(.source == "pipeline" and .type == "pipeline_started") | .run_id' "$test_root/output" | head -n 1)
  [ -n "$run_id" ] || fail "$1: no pipeline_started event"
  child="$workdir/.tracker/runs/$run_id"
  visits=$(wc -l <"$workdir/.tracker/continue-fixture/visits" | tr -d ' ')
  last=$(jq -Rr 'fromjson? | select(.source == "pipeline" and (.type | startswith("pipeline_"))) | .type' \
    "$child/activity.jsonl" | tail -n 1)
}

run_fixture granted 2
[ "$status" -eq 0 ] || fail 'granted: tracker exited non-zero'
[ "$visits" -eq 2 ] || fail "granted: worker ran $visits times, expected 2"
[ "$last" = pipeline_completed ] || fail "granted: last pipeline event is $last"
[ "$(cat "$workdir/.tracker/turn_overrides/Implement")" = 450 ] || fail 'granted: override missing after the run'
jq -e '.attempt == 1' "$child/continue-implement.json" >/dev/null || fail 'granted: continue marker missing'
jq -e '.outcome == "success" and (.context_updates.tool_stdout | split("\n") | any(. == "continue-ok"))' \
  "$child/ContinueImplement/status.json" >/dev/null || fail 'granted: ContinueImplement status is wrong'
printf 'ok - the real tracker restarts Implement once after a granted continue\n'

run_fixture exhausted 99
[ "$status" -ne 0 ] || fail 'exhausted: tracker exited zero'
[ "$visits" -eq 2 ] || fail "exhausted: worker ran $visits times, expected 2"
[ "$last" = pipeline_failed ] || fail "exhausted: last pipeline event is $last"
jq -e '.outcome == "fail" and (.context_updates.tool_stdout | split("\n") | any(. == "continue-exhausted"))' \
  "$child/ContinueImplement/status.json" >/dev/null || fail 'exhausted: ContinueImplement status is wrong'
jq -e '.context_updates.tool_stdout | split("\n") | any(. == "handoff-ok")' "$child/Handoff/status.json" >/dev/null ||
  fail 'exhausted: Handoff did not run'
printf 'ok - the real tracker hands off after the continue is exhausted\n'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `sh kata/tests/continue.sh`
Expected: `FAIL: first continue call failed` followed by `sh: kata/scripts/continue-implement.sh: No such file or directory` (or similar), exit 1.

- [ ] **Step 3: Write `kata/scripts/continue-implement.sh`**

```sh
#!/bin/sh
# ABOUTME: Grants Implement one warm continue after a steady-progress turn-limit breach.
# ABOUTME: Writes the tracker turn override once per run and reports exhaustion on the second call.
set -eu

: "${TRACKER_RUN_DIR:?TRACKER_RUN_DIR is required}"
: "${TRACKER_WORKDIR:?TRACKER_WORKDIR is required}"
command -v jq >/dev/null
# Both values are turn counts. The base must match Implement's max_turns in complete.dip;
# tracker honors an override only when it exceeds that base and stays at or under 1000.
implement_max_turns=300
continue_turns=150
marker="$TRACKER_RUN_DIR/continue-implement.json"
if [ -e "$marker" ]; then
  printf 'continue-exhausted\n'
  exit 1
fi
workspace=$(cd "$TRACKER_WORKDIR" && pwd -P)
override_dir="$workspace/.tracker/turn_overrides"
mkdir -p "$override_dir"
max_turns=$((implement_max_turns + continue_turns))
printf '%s\n' "$max_turns" >"$override_dir/Implement.tmp"
mv "$override_dir/Implement.tmp" "$override_dir/Implement"
jq -n --argjson max "$max_turns" --arg run "${TRACKER_RUN_ID:-unknown}" \
  '{attempt:1,max_turns:$max,run_id:$run}' >"$marker.tmp"
mv "$marker.tmp" "$marker"
printf 'continue-ok\n'
```

Then `chmod +x kata/scripts/continue-implement.sh` (the other scripts in that directory are executable).

- [ ] **Step 4: Run the test to verify it passes**

Run: `sh kata/tests/continue.sh`
Expected: three `ok - ...` lines, exit 0. If the `granted` case fails because tracker did not re-enter `Implement` after the restart edge, stop and report the activity log; do not change the edge semantics blind.

- [ ] **Step 5: Add the node and edges to `kata/complete.dip`**

Insert this block before the line `  tool Handoff` (currently line 106), keeping one blank line on each side:

```
  tool ContinueImplement
    label: "Grant one warm continue after a steady turn-limit breach"
    timeout: 10s
    command_file: scripts/continue-implement.sh
```

Replace these two edge lines (currently lines 120-121):

```
    Implement -> ReviewFreshEyes  on success
    Implement -> Handoff  on fail
```

with:

```
    Implement -> ReviewFreshEyes  when ctx.outcome = success
    Implement -> ContinueImplement  when ctx.turn_breach_class = operator_decision
    Implement -> Handoff  when ctx.outcome = fail
    ContinueImplement -> Implement  when ctx.outcome = success  restart: true
    ContinueImplement -> Handoff  when ctx.outcome = fail
```

The order matters: the breach edge must come before the fail edge, because tracker takes the first matching conditional edge.

- [ ] **Step 6: Validate the graph**

Run:

```sh
dippin check --format json kata/complete.dip | jq '.valid, .warnings'
tracker validate kata/complete.dip
```

Expected: `true` and `0`; tracker prints `complete.dip: valid (17 nodes, 30 edges)` (plus its known "unresolved condition variable" warning for runtime context).

- [ ] **Step 7: Extend `kata/tests/routes.sh`**

Replace the whole file with:

```sh
#!/bin/sh
# ABOUTME: Simulates concrete approval and rejection routes through the Dippin graph.
# ABOUTME: Checks single selection, repair bounds, and the one-time continue without running commands or models.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
scenario() {
  repairs=$1 closes=$2 handoffs=$3 continues=$4
  shift 4
  dippin simulate "$pipeline_dir/complete.dip" \
    --scenario ClaimNext.tool_marker=claim-ok "$@" >"$test_root/events" 2>"$test_root/summary"
  jq -se --argjson repairs "$repairs" --argjson closes "$closes" --argjson handoffs "$handoffs" \
    --argjson continues "$continues" '
    [.[] | select(.event == "node_enter") | .node] as $nodes |
    ($nodes | map(select(. == "ClaimNext")) | length) == 1 and
    ($nodes | map(select(. == "Repair")) | length) == $repairs and
    ($nodes | map(select(. == "CloseSelected")) | length) == $closes and
    ($nodes | map(select(. == "Handoff")) | length) == $handoffs and
    ($nodes | map(select(. == "ContinueImplement")) | length) == $continues
  ' "$test_root/events" >/dev/null
}
scenario 0 1 0 0
scenario 1 1 0 0 --scenario CheckApprovals.outcome=fail
scenario 1 0 1 0 --scenario CheckApprovals.outcome=fail --scenario ReCheckApprovals.outcome=fail
scenario 0 0 1 0 --scenario Implement.outcome=fail
scenario 0 1 1 0 --scenario CloseSelected.outcome=fail
# A steady breach that still ends in success never needs the continue.
scenario 0 1 0 0 --scenario Implement.turn_breach_class=operator_decision
# Simulation cannot grant the continue (its scenarios are sticky), so this covers the exhausted route only;
# tests/continue.sh drives the granted restart through the real tracker.
scenario 0 0 1 1 --scenario Implement.outcome=fail --scenario Implement.turn_breach_class=operator_decision \
  --scenario ContinueImplement.outcome=fail
jq -se '[.[] | select(.event == "node_enter") | .node] == ["ClaimNext", "Implement", "ContinueImplement", "Handoff", "Exit"]' \
  "$test_root/events" >/dev/null
dippin simulate "$pipeline_dir/complete.dip" --scenario ClaimNext.tool_marker=queue-empty \
  >"$test_root/events" 2>"$test_root/summary"
jq -se '[.[] | select(.event == "node_enter") | .node] == ["ClaimNext", "Exit"]' \
  "$test_root/events" >/dev/null
printf 'ok - simulated success, repair, rejection, worker/publication failure, exhausted continue, and empty queue routes\n'
```

- [ ] **Step 8: Run the routes test**

Run: `kata/tests/routes.sh`
Expected: the single `ok - ...` line, exit 0.

- [ ] **Step 9: Wire the new test into `kata/check`**

After the line `grep -F 'Repair' "$simulation_log" >/dev/null` add:

```sh
grep -F 'ContinueImplement' "$simulation_log" >/dev/null
```

After the line `"$KATA_DIR/tests/routes.sh"` add:

```sh
sh "$KATA_DIR/tests/continue.sh"
```

- [ ] **Step 10: Run the full check**

Run: `./kata/check`
Expected: every existing `ok - ...` line plus the three new ones; shellcheck silent; exit 0.

- [ ] **Step 11: Commit**

```sh
git status
git add kata/complete.dip kata/scripts/continue-implement.sh kata/tests/continue.sh kata/tests/routes.sh kata/check
git commit -m "feat(kata): grant one warm continue after a steady turn-limit breach"
```

---

### Task 2: Claim records the starting branch, clears a stale override, and removes handoff labels

**Files:**
- Modify: `kata/scripts/claim-next.sh:30-31` and `kata/scripts/claim-next.sh:183-192`
- Modify: `kata/tests/fake-kata.sh:13` and `kata/tests/fake-kata.sh:26-30`
- Modify: `kata/tests/check.sh:66-80` (`test_claim_and_persist`)

**Interfaces:**
- Consumes: the ready record's `labels` array (already inside `$selected_json`, the full ready record selected at lines 39-58).
- Produces: `selected.json` gains `start_branch` (the branch checked out before the claim). Task 3's handoff restores it. The claim deletes `<workspace>/.tracker/turn_overrides/Implement` before claiming and removes `needs-review` / `needs-decision` from the claimed kata when the ready record carries them.

- [ ] **Step 1: Extend the fixture and the failing test**

In `kata/tests/fake-kata.sh`, replace the `ready:ready|ready:conflict)` response line:

```sh
    printf '%s\n' '{"issues":[{"uid":"01ARZ3NDEKTSV4RRFFQ69G5FAV","short_id":"5fav","qualified_id":"demo#5fav","status":"open"}]}'
```

with:

```sh
    printf '%s\n' '{"issues":[{"uid":"01ARZ3NDEKTSV4RRFFQ69G5FAV","short_id":"5fav","qualified_id":"demo#5fav","status":"open","labels":["needs-review","task"]}]}'
```

and insert a case before the `*)` line:

```sh
  label:ready) ;;
```

In `kata/tests/check.sh`, `test_claim_and_persist`, insert before the line `output=$(FAKE_KATA_MODE=ready run_preflight "$repo")`:

```sh
  mkdir -p "$repo/.tracker/turn_overrides"
  printf '999\n' >"$repo/.tracker/turn_overrides/Implement"
```

and insert after the `--if-unowned` assertion line (the one ending `fail 'claim did not use full immutable identity'`):

```sh
  jq -e '.start_branch == "main"' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'starting branch was not persisted'
  [ ! -e "$repo/.tracker/turn_overrides/Implement" ] || fail 'stale turn override survived the claim'
  [ "$(grep -c '^label rm ' "$repo/.fake-kata-log")" -eq 1 ] || fail 'claim did not remove exactly one stale label'
  grep -F -- '--as kata-pipeline-test 01ARZ3NDEKTSV4RRFFQ69G5FAV needs-review --agent' "$repo/.fake-kata-log" >/dev/null || fail 'stale needs-review label was not removed as the run actor'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `kata/tests/check.sh`
Expected: `FAIL: starting branch was not persisted`, exit 1.

- [ ] **Step 3: Change `kata/scripts/claim-next.sh`**

Replace lines 30-31:

```sh
git symbolic-ref --quiet --short HEAD >/dev/null || { printf 'detached HEAD cannot be prepared automatically\n' >&2; exit 1; }
mkdir -p "$TRACKER_RUN_DIR"
```

with:

```sh
start_branch=$(git symbolic-ref --quiet --short HEAD) || { printf 'detached HEAD cannot be prepared automatically\n' >&2; exit 1; }
# A warm-continue override outlives its run; a stale one would inflate this run's worker budget.
rm -f "$workspace/.tracker/turn_overrides/Implement"
mkdir -p "$TRACKER_RUN_DIR"
```

Insert after the claim identity check (the block ending `printf 'claim response did not confirm identity and owner\n' >&2` / `exit 1` / `}`):

```sh
# A kata handed back after a review or decision still carries its handoff label; this run owns it now.
for label in needs-review needs-decision; do
  printf '%s' "$selected_json" | jq -e --arg label "$label" '(.labels // []) | any(. == $label)' >/dev/null || continue
  kata label rm --workspace "$workspace" --as "$actor" "$uid" "$label" --agent >/dev/null || {
    printf 'could not remove the %s label from %s\n' "$label" "$qualified_id" >&2
    exit 1
  }
done
```

Change the `selected.json` writer so it records the starting branch. The `jq -n` call becomes:

```sh
jq -n --arg uid "$uid" --arg short "$short_id" --arg qualified "$qualified_id" \
  --arg workspace "$workspace" --arg branch "$branch" --arg base "$base_commit" --arg actor "$actor" --argjson github "$github" \
  --arg start "$start_branch" \
  --argjson issue "$(printf '%s' "$claim_json" | jq '.issue')" \
  '{issue_uid:$uid,short_id:$short,qualified_id:$qualified,workspace:$workspace,branch:$branch,base_commit:$base,actor:$actor,start_branch:$start,github:$github,issue:$issue}' >"$state_tmp"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `kata/tests/check.sh`
Expected: every `ok - ...` line, exit 0.

- [ ] **Step 5: Run the full check and commit**

Run: `./kata/check` (expected: all green, exit 0). Then:

```sh
git status
git add kata/scripts/claim-next.sh kata/tests/fake-kata.sh kata/tests/check.sh
git commit -m "feat(kata): record the starting branch and clear handoff state at claim"
```

---

### Task 3: Handoff commits WIP, restores the starting branch, classifies the failure, and writes handoff.json

**Files:**
- Rewrite: `kata/scripts/handoff-selected.sh` (whole file)
- Create: `kata/tests/handoff.sh`
- Modify: `kata/check` (add the test after `continue.sh`)

**Interfaces:**
- Consumes: `selected.json` fields `workspace`, `issue_uid`, `qualified_id`, `actor`, `branch`, `base_commit`, `start_branch` (Task 2); run artifacts `question.md`, `handoff.md`, `CloseSelected/status.json`, `Review*/status.json`, `ReReview*/status.json`, `Implement/status.json`.
- Produces: `<run>/handoff.json` with exactly these keys: `run_id`, `issue_uid`, `qualified_id`, `reason` (one of `implement`, `turn_limit`, `review`, `publish`, `decision`, `unexpected_checkout`), `label` (`needs-review` or `needs-decision`), `branch`, `base_commit`, `wip_commit` (string or null), `start_branch`, `question` (string or null). Prints `handoff-ok` on stdout and exits 1. Task 7's board reads `handoff.json`; Task 6's report reads it too.

- [ ] **Step 1: Write the failing test `kata/tests/handoff.sh`**

```sh
#!/bin/sh
# ABOUTME: Checks the handoff script: failure classification, WIP commit, branch restore, label, comment, handoff.json.
# ABOUTME: Uses a fixture kata on PATH and disposable Git repositories; never touches a real daemon.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
script="$pipeline_dir/scripts/handoff-selected.sh"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
command -v jq >/dev/null

mkdir -p "$test_root/bin"
cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
# ABOUTME: Fixture kata for handoff tests: records label and comment calls for one known issue.
# ABOUTME: Fails on demand through fail-<verb> files so the test can observe partial handoffs.
set -eu
verb=$1
shift
action=
if [ "$verb" = label ]; then action=$1; shift; fi
[ "$1" = --workspace ] || exit 91
fixture="$2/.tracker/handoff-fixture"
shift 2
printf '%s %s\n' "$verb${action:+ $action}" "$*" >>"$fixture/kata.log"
[ ! -e "$fixture/fail-$verb" ] || exit 95
[ "$1" = --as ] && [ "$2" = kata-pipeline-test ] || exit 92
shift 2
case "$verb:$action" in
  label:add)
    [ "$#" -eq 3 ] && [ "$1" = 01ARZ3NDEKTSV4RRFFQ69G5FAV ] && [ "$3" = --agent ] || exit 93
    printf '%s\n' "$2" >>"$fixture/labels"
    ;;
  comment:)
    [ "$#" -eq 4 ] && [ "$1" = 01ARZ3NDEKTSV4RRFFQ69G5FAV ] && [ "$2" = --body-file ] && [ "$4" = --agent ] || exit 94
    cp "$3" "$fixture/comment.md"
    ;;
  *) exit 96 ;;
esac
SH
chmod +x "$test_root/bin/kata"
export PATH="$test_root/bin:$PATH"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || cat "$test_root/output" >&2
  exit 1
}

new_repo() {
  repo="$test_root/$1"
  git init -q -b main "$repo"
  repo=$(cd "$repo" && pwd -P)
  git -C "$repo" config user.name 'Pipeline check'
  git -C "$repo" config user.email 'pipeline-check@example.invalid'
  git -C "$repo" config commit.gpgsign false
  printf '.tracker/\n' >"$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit -qm 'test: seed handoff repository'
  base=$(git -C "$repo" rev-parse HEAD)
  git -C "$repo" switch -qc kata/5fav-test
  run_dir="$repo/.tracker/runs/test"
  fixture="$repo/.tracker/handoff-fixture"
  mkdir -p "$run_dir" "$fixture" "$repo/.tracker/turn_overrides"
  printf '450\n' >"$repo/.tracker/turn_overrides/Implement"
  jq -n --arg workspace "$repo" --arg base "$base" '{workspace:$workspace,issue_uid:"01ARZ3NDEKTSV4RRFFQ69G5FAV",
    short_id:"5fav",qualified_id:"demo#5fav",branch:"kata/5fav-test",base_commit:$base,actor:"kata-pipeline-test",
    start_branch:"main",github:null}' >"$run_dir/selected.json"
}

handoff() {
  if (cd "$repo" && TRACKER_RUN_DIR="$run_dir" TRACKER_RUN_ID=test TRACKER_WORKDIR="$repo" sh "$script") \
    >"$test_root/output" 2>&1; then
    fail "$1: handoff exited zero"
  fi
}

expect_record() {
  jq -e --arg reason "$1" --arg label "$2" '.reason == $reason and .label == $label' "$run_dir/handoff.json" >/dev/null ||
    fail "handoff.json does not record $1 with $2"
  [ "$(cat "$fixture/labels")" = "$2" ] || fail "kata did not receive exactly the $2 label"
  [ ! -e "$repo/.tracker/turn_overrides/Implement" ] || fail 'turn override survived the handoff'
  grep -Fx 'handoff-ok' "$test_root/output" >/dev/null || fail 'handoff-ok was not printed'
}

new_repo implement
printf 'half done\n' >"$repo/partial.txt"
handoff implement
expect_record implement needs-review
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'implement: starting branch was not restored'
[ -z "$(git -C "$repo" status --porcelain --untracked-files=normal)" ] || fail 'implement: working tree is dirty after the handoff'
[ "$(git -C "$repo" rev-parse main)" = "$base" ] || fail 'implement: main moved'
wip=$(git -C "$repo" rev-parse kata/5fav-test)
[ "$wip" != "$base" ] || fail 'implement: no WIP commit on the task branch'
[ "$(git -C "$repo" log -1 --format=%s kata/5fav-test)" = 'wip(kata): demo#5fav handoff from run test' ] ||
  fail 'implement: WIP subject is wrong'
git -C "$repo" show --stat --format= kata/5fav-test | grep -F 'partial.txt' >/dev/null || fail 'implement: WIP commit lacks the dirty file'
jq -e --arg base "$base" --arg wip "$wip" '.run_id == "test" and .issue_uid == "01ARZ3NDEKTSV4RRFFQ69G5FAV" and
  .qualified_id == "demo#5fav" and .branch == "kata/5fav-test" and .base_commit == $base and .wip_commit == $wip and
  .start_branch == "main" and .question == null and
  keys == ["base_commit","branch","issue_uid","label","qualified_id","question","reason","run_id","start_branch","wip_commit"]' \
  "$run_dir/handoff.json" >/dev/null || fail 'implement: handoff.json fields are wrong'
grep -F 'Attempted the selected kata on branch kata/5fav-test.' "$fixture/comment.md" >/dev/null ||
  fail 'implement: default handoff text is missing from the comment'
grep -Fx "Branch: kata/5fav-test (base $base, wip $wip)" "$fixture/comment.md" >/dev/null ||
  fail 'implement: branch line is missing from the comment'
grep -Fx 'Run: test' "$fixture/comment.md" >/dev/null || fail 'implement: run line is missing from the comment'
if grep -F 'Question:' "$fixture/comment.md" >/dev/null; then fail 'implement: comment has a question line'; fi
printf 'ok - a worker failure commits WIP, restores the starting branch, labels needs-review, and records handoff.json\n'

new_repo decision
mkdir -p "$run_dir/Implement"
printf '{"outcome":"fail","context_updates":{"turn_breach_class":"operator_decision"}}\n' >"$run_dir/Implement/status.json"
printf 'Should the CLI accept --format=json\nas well as --json?\n' >"$run_dir/question.md"
handoff decision
expect_record decision needs-decision
jq -e '.question == "Should the CLI accept --format=json\nas well as --json?" and .wip_commit == null' "$run_dir/handoff.json" >/dev/null ||
  fail 'decision: question or wip_commit is wrong'
grep -F 'Question: Should the CLI accept --format=json' "$fixture/comment.md" >/dev/null || fail 'decision: question is missing from the comment'
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'decision: starting branch was not restored'
printf 'ok - a written question outranks a turn limit and labels needs-decision\n'

new_repo publish
mkdir -p "$run_dir/CloseSelected" "$run_dir/ReviewCorrectness"
printf '{"outcome":"fail"}\n' >"$run_dir/CloseSelected/status.json"
printf '{"outcome":"success"}\n' >"$run_dir/ReviewCorrectness/status.json"
printf 'Push was rejected by the remote.\n' >"$run_dir/handoff.md"
handoff publish
expect_record publish needs-review
[ "$(sed -n '1p' "$fixture/comment.md")" = 'Push was rejected by the remote.' ] || fail 'publish: custom handoff text does not lead the comment'
printf 'ok - a publication failure outranks reviews and keeps the custom handoff text\n'

new_repo review
mkdir -p "$run_dir/ReReviewScope"
printf '{"outcome":"success"}\n' >"$run_dir/ReReviewScope/status.json"
handoff review
expect_record review needs-review
printf 'ok - a rejected review is recorded as review\n'

new_repo turn-limit
mkdir -p "$run_dir/Implement"
printf '{"outcome":"fail","context_updates":{"turn_breach_class":"operator_decision"}}\n' >"$run_dir/Implement/status.json"
handoff turn-limit
expect_record turn_limit needs-review
printf 'ok - a steady turn-limit breach without a question is recorded as turn_limit\n'

new_repo wrong-branch
git -C "$repo" switch -qc feat/elsewhere
printf 'stray\n' >"$repo/stray.txt"
handoff wrong-branch
expect_record unexpected_checkout needs-review
[ "$(git -C "$repo" branch --show-current)" = feat/elsewhere ] || fail 'wrong-branch: checkout changed'
[ -n "$(git -C "$repo" status --porcelain --untracked-files=normal)" ] || fail 'wrong-branch: working tree was touched'
jq -e '.wip_commit == null' "$run_dir/handoff.json" >/dev/null || fail 'wrong-branch: wip_commit is not null'
printf 'ok - an unexpected checkout is reported without touching the tree\n'

new_repo kata-failure
: >"$fixture/fail-comment"
handoff kata-failure
[ ! -e "$run_dir/handoff.json" ] || fail 'kata-failure: handoff.json was written after a failed comment'
[ -e "$repo/.tracker/turn_overrides/Implement" ] || fail 'kata-failure: turn override was removed after a failed comment'
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'kata-failure: starting branch was not restored before the comment'
if grep -Fx 'handoff-ok' "$test_root/output" >/dev/null; then fail 'kata-failure: handoff-ok was printed despite the failed comment'; fi
printf 'ok - a failed kata comment leaves no handoff record\n'

new_repo legacy
jq 'del(.start_branch)' "$run_dir/selected.json" >"$run_dir/selected.json.tmp"
mv "$run_dir/selected.json.tmp" "$run_dir/selected.json"
handoff legacy
grep -F 'selected.json has no start_branch' "$test_root/output" >/dev/null || fail 'legacy: message is missing'
[ ! -e "$fixture/kata.log" ] || fail 'legacy: kata was called'
[ "$(git -C "$repo" branch --show-current)" = kata/5fav-test ] || fail 'legacy: checkout changed'
printf 'ok - a run claimed before the starting branch was recorded stops for inspection\n'

new_repo no-claim
rm "$run_dir/selected.json"
handoff no-claim
grep -F 'no claimed kata exists to hand off' "$test_root/output" >/dev/null || fail 'no-claim: message is missing'
[ ! -e "$fixture/kata.log" ] || fail 'no-claim: kata was called'
printf 'ok - a missing claim is refused before any kata call\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh kata/tests/handoff.sh`
Expected: `FAIL: handoff.json does not record implement with needs-review` (the current script writes no `handoff.json`), exit 1.

- [ ] **Step 3: Rewrite `kata/scripts/handoff-selected.sh`**

Replace the whole file with:

```sh
#!/bin/sh
# ABOUTME: Leaves a failed claimed kata open and reviewable: label, comment, WIP commit, starting branch restored.
# ABOUTME: Classifies the failure from run artifacts and records it in handoff.json for the board.
set -eu

test -n "${TRACKER_RUN_DIR:-}" || { printf 'TRACKER_RUN_DIR is required\n' >&2; exit 1; }
test -n "${TRACKER_WORKDIR:-}" || { printf 'TRACKER_WORKDIR is required\n' >&2; exit 1; }
run_id=${TRACKER_RUN_ID:-unknown}
state="$TRACKER_RUN_DIR/selected.json"
[ -f "$state" ] || { printf 'no claimed kata exists to hand off\n' >&2; exit 1; }
workspace=$(jq -er '.workspace' "$state")
uid=$(jq -er '.issue_uid' "$state")
qualified_id=$(jq -er '.qualified_id' "$state")
actor=$(jq -er '.actor' "$state")
branch=$(jq -er '.branch' "$state")
base_commit=$(jq -er '.base_commit' "$state")
start_branch=$(jq -er '.start_branch' "$state") || {
  printf 'selected.json has no start_branch; this run predates the branch restore and needs manual inspection\n' >&2
  exit 1
}
workspace=$(cd "$workspace" && pwd -P)
[ "$workspace" = "$(cd "$TRACKER_WORKDIR" && pwd -P)" ] || { printf 'tracker workspace changed\n' >&2; exit 1; }
cd "$workspace"

reason=implement
question=
wip_commit=
current_branch=$(git symbolic-ref --quiet --short HEAD || true)
if [ "$current_branch" = "$branch" ]; then
  # Later evidence outranks earlier: a question, then a publication failure, then any review, then a turn limit.
  if [ -s "$TRACKER_RUN_DIR/question.md" ]; then
    reason=decision
    question=$(cat "$TRACKER_RUN_DIR/question.md")
  elif jq -e '.outcome == "fail"' "$TRACKER_RUN_DIR/CloseSelected/status.json" >/dev/null 2>&1; then
    reason=publish
  else
    for review in ReviewCorrectness ReviewScope ReReviewCorrectness ReReviewScope; do
      [ ! -f "$TRACKER_RUN_DIR/$review/status.json" ] || reason=review
    done
    if [ "$reason" = implement ] &&
      jq -e '.outcome == "fail" and .context_updates.turn_breach_class == "operator_decision"' \
        "$TRACKER_RUN_DIR/Implement/status.json" >/dev/null 2>&1; then
      reason=turn_limit
    fi
  fi
  if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
    git add -A
    git commit -q -m "wip(kata): $qualified_id handoff from run $run_id"
    wip_commit=$(git rev-parse HEAD)
  fi
  git switch -q "$start_branch"
else
  reason=unexpected_checkout
fi

label=needs-review
[ "$reason" != decision ] || label=needs-decision
if [ ! -s "$TRACKER_RUN_DIR/handoff.md" ]; then
  printf 'Attempted the selected kata on branch %s. The bounded run did not earn both SHA-bound approvals. Inspect tracker run %s and the branch diff; unresolved review or test findings remain.\n' "$branch" "$run_id" >"$TRACKER_RUN_DIR/handoff.md"
fi
comment="$TRACKER_RUN_DIR/handoff-comment.md"
{
  cat "$TRACKER_RUN_DIR/handoff.md"
  printf '\nBranch: %s (base %s, wip %s)\nRun: %s\n' "$branch" "$base_commit" "${wip_commit:-none}" "$run_id"
  [ -z "$question" ] || printf 'Question: %s\n' "$question"
} >"$comment"
kata label add --workspace "$workspace" --as "$actor" "$uid" "$label" --agent
kata comment --workspace "$workspace" --as "$actor" "$uid" --body-file "$comment" --agent
jq -n --arg run "$run_id" --arg uid "$uid" --arg qualified "$qualified_id" --arg reason "$reason" --arg label "$label" \
  --arg branch "$branch" --arg base "$base_commit" --arg wip "$wip_commit" --arg start "$start_branch" --arg question "$question" \
  '{run_id:$run,issue_uid:$uid,qualified_id:$qualified,reason:$reason,label:$label,branch:$branch,base_commit:$base,
    wip_commit:(if $wip == "" then null else $wip end),start_branch:$start,
    question:(if $question == "" then null else $question end)}' >"$TRACKER_RUN_DIR/handoff.json.tmp"
mv "$TRACKER_RUN_DIR/handoff.json.tmp" "$TRACKER_RUN_DIR/handoff.json"
# The warm-continue override belongs to this run's worker; the next run starts from the base budget.
rm -f "$workspace/.tracker/turn_overrides/Implement"
printf 'handoff-ok\n'
exit 1
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `sh kata/tests/handoff.sh`
Expected: nine `ok - ...` lines, exit 0.

- [ ] **Step 5: Wire the test into `kata/check`**

After the line `sh "$KATA_DIR/tests/continue.sh"` add:

```sh
sh "$KATA_DIR/tests/handoff.sh"
```

- [ ] **Step 6: Run the full check and commit**

Run: `./kata/check` (expected: all green, exit 0; `kata/tests/board.sh` still passes because its fixture graph does not use the real handoff yet). Then:

```sh
git status
git add kata/scripts/handoff-selected.sh kata/tests/handoff.sh kata/check
git commit -m "feat(kata): hand off failed katas with WIP, labels, and a handoff record"
```

---

### Task 4: Closure clears the warm-continue override

**Files:**
- Modify: `kata/scripts/close-selected.sh:122` (before `printf 'close-ok\n'`)
- Modify: `kata/tests/publish.sh:117-118` (the `new_case publish` block)

**Interfaces:**
- Consumes: nothing new.
- Produces: after a successful closure, `<workspace>/.tracker/turn_overrides/Implement` no longer exists.

- [ ] **Step 1: Write the failing assertion**

In `kata/tests/publish.sh`, after the line `new_case publish` insert:

```sh
mkdir -p "$repo/.tracker/turn_overrides"
printf '450\n' >"$repo/.tracker/turn_overrides/Implement"
```

and after the line `run_close || { cat "$case_dir/output" >&2; exit 1; }` insert:

```sh
[ ! -e "$repo/.tracker/turn_overrides/Implement" ] || { printf 'FAIL: closure kept the turn override\n' >&2; exit 1; }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh kata/tests/publish.sh`
Expected: `FAIL: closure kept the turn override`, exit 1.

- [ ] **Step 3: Delete the override in `kata/scripts/close-selected.sh`**

Insert before the final line `printf 'close-ok\n'`:

```sh
# The warm-continue override belongs to this run's worker; the next run starts from the base budget.
rm -f "$workspace/.tracker/turn_overrides/Implement"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `sh kata/tests/publish.sh`
Expected: every `ok - ...` line, exit 0.

- [ ] **Step 5: Run the full check and commit**

Run: `./kata/check` (expected: all green). Then:

```sh
git status
git add kata/scripts/close-selected.sh kata/tests/publish.sh
git commit -m "feat(kata): clear the warm-continue override after closure"
```

---

### Task 5: `kata/answer` comments a reply and releases the pipeline claim

**Files:**
- Create: `kata/answer` (executable, no extension)
- Create: `kata/tests/answer.sh`
- Modify: `kata/check` (add the test after `board.sh`; add `"$KATA_DIR/answer"` to the shellcheck line)

**Interfaces:**
- Consumes: `kata show <ref> --json` (`.issue.uid`, `.issue.status`, `.issue.owner`), `kata unassign <uid> --expect-owner <owner> --comment <text> --json`, `kata list --status open --limit 0 --json` (`.issues[].labels`).
- Produces: the command `answer <issue-ref> "<text>"`, run from the target Git root. Exit 0 prints `Owner: <owner or nobody>` and `Labels: <comma list or none>`. Exit 2 for usage errors or blank text, exit 1 when the kata is not open, unowned, or owned by a non-pipeline actor. Task 6's report prints this command's absolute path.

- [ ] **Step 1: Write the failing test `kata/tests/answer.sh`**

```sh
#!/bin/sh
# ABOUTME: Checks kata/answer: refuses bad targets, comments and unassigns a pipeline-owned kata, reports the result.
# ABOUTME: Uses a fixture kata on PATH; never touches a real daemon.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
answer="$pipeline_dir/answer"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
command -v jq >/dev/null

mkdir -p "$test_root/bin"
cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
# ABOUTME: Fixture kata for answer tests: one issue whose status and owner live in files.
# ABOUTME: Records every call and rejects anything but show, unassign, and list.
set -eu
verb=$1
shift
[ "$1" = --workspace ] || exit 91
fixture="$2/.tracker/answer-fixture"
shift 2
printf '%s %s\n' "$verb" "$*" >>"$fixture/kata.log"
owner=$(cat "$fixture/owner")
case "$verb" in
  show)
    [ "$#" -eq 2 ] && [ "$2" = --json ] || exit 92
    jq -n --arg status "$(cat "$fixture/status")" --arg owner "$owner" \
      '{issue:{uid:"01ARZ3NDEKTSV4RRFFQ69G5FAV",qualified_id:"demo#5fav",status:$status,owner:(if $owner == "" then null else $owner end)}}'
    ;;
  unassign)
    [ "$#" -eq 6 ] && [ "$1" = 01ARZ3NDEKTSV4RRFFQ69G5FAV ] && [ "$2" = --expect-owner ] && [ "$3" = "$owner" ] &&
      [ "$4" = --comment ] && [ "$6" = --json ] || exit 93
    printf '%s\n' "$5" >"$fixture/comment"
    : >"$fixture/owner"
    printf '%s\n' '{"issue":{"uid":"01ARZ3NDEKTSV4RRFFQ69G5FAV","owner":null}}'
    ;;
  list)
    [ "$*" = '--status open --limit 0 --json' ] || exit 94
    printf '%s\n' '{"issues":[{"uid":"01ARZ3NDEKTSV4RRFFQ69G5FAV","qualified_id":"demo#5fav","status":"open","labels":["needs-decision","task"]}]}'
    ;;
  *) exit 95 ;;
esac
SH
chmod +x "$test_root/bin/kata"
export PATH="$test_root/bin:$PATH"

repo="$test_root/repo"
git init -q -b main "$repo"
repo=$(cd "$repo" && pwd -P)
fixture="$repo/.tracker/answer-fixture"
mkdir -p "$fixture"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || cat "$test_root/output" >&2
  exit 1
}

reset_fixture() {
  printf '%s\n' "$1" >"$fixture/status"
  printf '%s' "$2" >"$fixture/owner"
  rm -f "$fixture/kata.log" "$fixture/comment"
}

run_answer() {
  status=0
  (cd "$repo" && "$answer" "$@") >"$test_root/output" 2>&1 || status=$?
}

reject() {
  run_answer demo#5fav "$1"
  [ "$status" -eq "$2" ] || fail "$4: exit status $status, expected $2"
  grep -F "$3" "$test_root/output" >/dev/null || fail "$4: message '$3' is missing"
  if grep -F 'unassign' "$fixture/kata.log" >/dev/null 2>&1; then fail "$4: unassign was called"; fi
}

reset_fixture open kata-pipeline-abc
reject '   ' 2 'answer text is empty' blank
[ ! -e "$fixture/kata.log" ] || fail 'blank: kata was called'
reset_fixture open harper
reject 'Ship it' 1 'not a pipeline actor' person-owned
reset_fixture open ''
reject 'Ship it' 1 'is unowned' unowned
reset_fixture closed kata-pipeline-abc
reject 'Ship it' 1 'not open' closed
printf 'ok - answer refuses blank text, person-owned, unowned, and closed katas\n'

reset_fixture open kata-pipeline-abc
run_answer demo#5fav 'Ship it'
[ "$status" -eq 0 ] || fail "answer failed with status $status"
grep -Fx 'unassign 01ARZ3NDEKTSV4RRFFQ69G5FAV --expect-owner kata-pipeline-abc --comment Ship it --json' "$fixture/kata.log" >/dev/null ||
  fail 'unassign call is wrong'
[ "$(cat "$fixture/comment")" = 'Ship it' ] || fail 'comment text was not passed through'
grep -Fx 'Owner: nobody' "$test_root/output" >/dev/null || fail 'owner line is missing'
grep -Fx 'Labels: needs-decision,task' "$test_root/output" >/dev/null || fail 'labels line is missing'
printf 'ok - answer comments the reply, releases the pipeline claim, and reports owner and labels\n'

run_answer --help
[ "$status" -eq 0 ] || fail "--help exited $status"
grep -F 'Usage: answer' "$test_root/output" >/dev/null || fail '--help lacks usage'
run_answer demo#5fav
[ "$status" -eq 2 ] || fail "missing text exited $status, expected 2"
grep -F 'Usage: answer' "$test_root/output" >/dev/null || fail 'missing text lacks usage'
printf 'ok - answer prints usage for --help and wrong arguments\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh kata/tests/answer.sh`
Expected: `FAIL: blank: exit status 127, expected 2` (no `kata/answer` yet), exit 1.

- [ ] **Step 3: Write `kata/answer`**

```sh
#!/bin/sh
# ABOUTME: Answers a kata the board handed off: comments the reply and releases the pipeline claim.
# ABOUTME: Refuses katas owned by anyone but a pipeline actor so it never takes a person's claim.
set -eu

usage() {
  printf 'Usage: answer <issue-ref> "<text>"\nRun from the target Git root. Comments the text on the kata and releases the pipeline claim so the next board run can pick it up.\n'
}
if [ "${1:-}" = --help ]; then
  usage
  exit 0
fi
[ "$#" -eq 2 ] || { usage >&2; exit 2; }
ref=$1
text=$2
[ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ] || { printf 'answer text is empty\n' >&2; exit 2; }
command -v git >/dev/null
command -v jq >/dev/null
command -v kata >/dev/null
workspace=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)
issue=$(kata show --workspace "$workspace" "$ref" --json)
uid=$(printf '%s' "$issue" | jq -er '.issue.uid')
status=$(printf '%s' "$issue" | jq -er '.issue.status')
owner=$(printf '%s' "$issue" | jq -r '.issue.owner // ""')
[ "$status" = open ] || { printf '%s is %s, not open\n' "$ref" "$status" >&2; exit 1; }
case "$owner" in
  '') printf '%s is unowned; nothing to hand back\n' "$ref" >&2; exit 1 ;;
  kata-pipeline-*) ;;
  *) printf '%s is owned by %s, not a pipeline actor; refusing to take a claim\n' "$ref" "$owner" >&2; exit 1 ;;
esac
kata unassign --workspace "$workspace" "$uid" --expect-owner "$owner" --comment "$text" --json >/dev/null
printf 'Owner: %s\n' "$(kata show --workspace "$workspace" "$uid" --json | jq -r '.issue.owner // "nobody"')"
printf 'Labels: %s\n' "$(kata list --workspace "$workspace" --status open --limit 0 --json |
  jq -r --arg uid "$uid" '[.issues[] | select(.uid == $uid) | (.labels // [])[]] | if length == 0 then "none" else join(",") end')"
```

Then `chmod +x kata/answer`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `sh kata/tests/answer.sh`
Expected: three `ok - ...` lines, exit 0.

- [ ] **Step 5: Wire the test and shellcheck into `kata/check`**

After the line `sh "$KATA_DIR/tests/board.sh"` add:

```sh
sh "$KATA_DIR/tests/answer.sh"
```

Change the shellcheck line to:

```sh
shellcheck "$KATA_DIR/check" "$KATA_DIR/retry-implementation" "$KATA_DIR/answer" "$KATA_DIR"/scripts/*.sh "$KATA_DIR"/tests/*.sh
```

- [ ] **Step 6: Run the full check and commit**

Run: `./kata/check` (expected: all green). Then:

```sh
git status
git add kata/answer kata/tests/answer.sh kata/check
git commit -m "feat(kata): add answer to reply to a handed-off kata and release its claim"
```

---

### Task 6: `kata/board-report` prints the morning review

**Files:**
- Create: `kata/board-report` (executable, no extension)
- Create: `kata/tests/report.sh`
- Modify: `kata/check` (add the test after `answer.sh`; add `"$KATA_DIR/board-report"` to the shellcheck line)

**Interfaces:**
- Consumes: the board ledger `<workspace>/.tracker/runs/<board-run-id>/board/state.json` with runs of kind `completed` (fields `issue_uid`, `branch`, `pr_url`), `failed` (field `issue_uid`), and `empty`; optional `stop_reason`; each completed child's `selected.json` (`qualified_id`); each failed child's `handoff.json` (Task 3's keys); `kata list --status open --limit 0 --json`; `kata/answer` (Task 5) as a sibling file.
- Produces: the command `board-report [--json] [BOARD_RUN_ID]`, run from the target Git root. Text on stdout, or with `--json` one object `{board_run_id, workspace, finished, stop_reason, completed, needs_decision, needs_review, remaining}` where every item in the four lists has exactly the keys `qualified_id, issue_uid, run_id, branch, base_commit, wip_commit, pr_url, reason, question, owner, labels, next` (nulls or `[]` where absent). Task 7's board runs this command at the end of a board.

- [ ] **Step 1: Write the failing test `kata/tests/report.sh`**

```sh
#!/bin/sh
# ABOUTME: Checks kata/board-report against fixture ledgers, handoff records, and a fixture open-issue list.
# ABOUTME: Compares the text report exactly and checks the JSON shape; never touches a real daemon.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
report="$pipeline_dir/board-report"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
command -v jq >/dev/null

mkdir -p "$test_root/bin"
cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
# ABOUTME: Fixture kata for report tests: answers only the open-issue listing.
# ABOUTME: Rejects every other call so the report stays read-only.
set -eu
[ "$1" = list ] && [ "$2" = --workspace ] || exit 91
shift 3
[ "$*" = '--status open --limit 0 --json' ] || exit 92
cat <<'JSON'
{"issues":[
  {"uid":"01DECISION0000000000000000","qualified_id":"demo#n4vr","status":"open","owner":"kata-pipeline-d1d1d1d1d1d1","labels":["needs-decision"]},
  {"uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","status":"open","owner":"kata-pipeline-r1r1r1r1r1r1","labels":["needs-review","task"]},
  {"uid":"01UNTOUCHED000000000000000","qualified_id":"demo#a2j0","status":"open","owner":"kata-pipeline-b20d9e898b16","labels":null},
  {"uid":"01UNOWNED00000000000000000","qualified_id":"demo#zz11","status":"open","owner":null,"labels":["task"]}
]}
JSON
SH
chmod +x "$test_root/bin/kata"
export PATH="$test_root/bin:$PATH"

repo="$test_root/repo"
git init -q -b main "$repo"
repo=$(cd "$repo" && pwd -P)
runs="$repo/.tracker/runs"
base=1234abcd1234abcd1234abcd1234abcd1234abcd
head=9abcdef09abcdef09abcdef09abcdef09abcdef0
wip=5678ef015678ef015678ef015678ef015678ef01

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || cat "$test_root/output" >&2
  exit 1
}

ledger() {
  mkdir -p "$runs/$1/board"
  printf '%s\n' "$2" >"$runs/$1/board/state.json"
}

handoff() {
  mkdir -p "$runs/$1"
  printf '%s\n' "$2" >"$runs/$1/handoff.json"
}

ledger older '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":false,"stop_reason":"three consecutive failed children","runs":[
  {"run_id":"t1t1t1t1t1t1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-t1t1t1t1t1t1","reason":"turn_limit","label":"needs-review"}]}'
touch -t 202001010000 "$runs/older/board/state.json"
ledger newer '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"c1c1c1c1c1c1","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-c1c1c1c1c1c1","commit":"'"$head"'","github":{"remote":"origin","repository":"o/r","base_branch":"main"},"pr_url":"https://github.com/o/r/pull/12"},
  {"run_id":"d1d1d1d1d1d1","kind":"failed","issue_uid":"01DECISION0000000000000000","branch":"kata/n4vr-d1d1d1d1d1d1","reason":"decision","label":"needs-decision"},
  {"run_id":"r1r1r1r1r1r1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-r1r1r1r1r1r1","reason":"review","label":"needs-review"},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"}]}'
mkdir -p "$runs/c1c1c1c1c1c1"
printf '%s\n' '{"issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav"}' >"$runs/c1c1c1c1c1c1/selected.json"
handoff d1d1d1d1d1d1 '{"run_id":"d1d1d1d1d1d1","issue_uid":"01DECISION0000000000000000","qualified_id":"demo#n4vr","reason":"decision","label":"needs-decision","branch":"kata/n4vr-d1d1d1d1d1d1","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":"Should the CLI accept --format=json\nas well as --json?"}'
handoff r1r1r1r1r1r1 '{"run_id":"r1r1r1r1r1r1","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"review","label":"needs-review","branch":"kata/bq4e-r1r1r1r1r1r1","base_commit":"'"$base"'","wip_commit":"'"$wip"'","start_branch":"main","question":null}'
handoff t1t1t1t1t1t1 '{"run_id":"t1t1t1t1t1t1","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"turn_limit","label":"needs-review","branch":"kata/bq4e-t1t1t1t1t1t1","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":null}'

cat >"$test_root/expected" <<EXPECTED
Board newer in $repo: finished
Completed (1)
  demo#5fav  kata/5fav-c1c1c1c1c1c1  https://github.com/o/r/pull/12
Needs decision (1)
  demo#n4vr  Q: Should the CLI accept --format=json as well as --json?
      $pipeline_dir/answer demo#n4vr "<your answer>"
Needs review (1)
  demo#bq4e  review rejected; branch kata/bq4e-r1r1r1r1r1r1 (base 1234abcd, wip 5678ef01); run r1r1r1r1r1r1
      git diff $base..kata/bq4e-r1r1r1r1r1r1
      $pipeline_dir/answer demo#bq4e "<guidance>"
Remaining open (2)
  demo#a2j0  owned by kata-pipeline-b20d9e898b16
  demo#zz11  owned by nobody, labels task
EXPECTED
(cd "$repo" && "$report") >"$test_root/output" 2>&1 || fail 'report failed for the newest run'
diff -u "$test_root/expected" "$test_root/output" || fail 'text report differs from the expected output'
printf 'ok - the text report picks the newest board run and groups its katas\n'

(cd "$repo" && "$report" --json newer) >"$test_root/report.json" 2>"$test_root/output" || fail 'json report failed'
jq -e --arg repo "$repo" --arg answer "$pipeline_dir/answer" --arg base "$base" --arg wip "$wip" '
  .board_run_id == "newer" and .workspace == $repo and .finished == true and .stop_reason == null and
  [.completed[].qualified_id] == ["demo#5fav"] and .completed[0].run_id == "c1c1c1c1c1c1" and
  .completed[0].pr_url == "https://github.com/o/r/pull/12" and .completed[0].next == [] and
  [.needs_decision[].qualified_id] == ["demo#n4vr"] and
  .needs_decision[0].question == "Should the CLI accept --format=json\nas well as --json?" and
  .needs_decision[0].owner == "kata-pipeline-d1d1d1d1d1d1" and .needs_decision[0].labels == ["needs-decision"] and
  .needs_decision[0].next == ["\($answer) demo#n4vr \"<your answer>\""] and
  [.needs_review[].qualified_id] == ["demo#bq4e"] and .needs_review[0].reason == "review" and
  .needs_review[0].base_commit == $base and .needs_review[0].wip_commit == $wip and
  .needs_review[0].next == ["git diff \($base)..kata/bq4e-r1r1r1r1r1r1", "\($answer) demo#bq4e \"<guidance>\""] and
  [.remaining[].qualified_id] == ["demo#a2j0","demo#zz11"] and [.remaining[].labels] == [[],["task"]] and
  [.remaining[].owner] == ["kata-pipeline-b20d9e898b16",null] and
  ([.completed[], .needs_decision[], .needs_review[], .remaining[]] |
    all(keys == ["base_commit","branch","issue_uid","labels","next","owner","pr_url","qualified_id","question","reason","run_id","wip_commit"]))
' "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'json report has the wrong shape'; }
printf 'ok - the JSON report carries every field for agents\n'

(cd "$repo" && "$report" older) >"$test_root/output" 2>&1 || fail 'report failed for a named run'
grep -Fx "Board older in $repo: stopped" "$test_root/output" >/dev/null || fail 'older: header is wrong'
grep -Fx 'Stop reason: three consecutive failed children' "$test_root/output" >/dev/null || fail 'older: stop reason is missing'
grep -Fx '  demo#bq4e  turn limit reached twice; branch kata/bq4e-t1t1t1t1t1t1 (base 1234abcd, wip none); run t1t1t1t1t1t1' \
  "$test_root/output" >/dev/null || fail 'older: review row is wrong'
grep -Fx 'Remaining open (3)' "$test_root/output" >/dev/null || fail 'older: remaining count is wrong'
printf 'ok - a named stopped run reports its stop reason\n'

status=0
(cd "$repo" && "$report" missing) >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "missing run exited $status, expected 1"
grep -F 'no board ledger' "$test_root/output" >/dev/null || fail 'missing run: message is wrong'
rm "$runs/r1r1r1r1r1r1/handoff.json"
status=0
(cd "$repo" && "$report" newer) >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "missing handoff exited $status, expected 1"
grep -F 'failed child r1r1r1r1r1r1 has no handoff record' "$test_root/output" >/dev/null || fail 'missing handoff: message is wrong'
printf 'ok - a missing ledger or handoff record is an error, not a guess\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh kata/tests/report.sh`
Expected: `FAIL: report failed for the newest run` with a "not found" line from the shell, exit 1.

- [ ] **Step 3: Write `kata/board-report`**

```sh
#!/bin/sh
# ABOUTME: Prints the morning review for a board run: completed katas, katas needing a decision or review, remaining open.
# ABOUTME: Reads the board ledger, child records, and the live open list read-only; --json emits the same data for agents.
set -eu

usage() {
  printf 'Usage: board-report [--json] [BOARD_RUN_ID]\nRun from the target Git root. Without an ID it reports the newest board run under .tracker/runs.\n'
}
format=text
if [ "${1:-}" = --json ]; then
  format=json
  shift
fi
if [ "${1:-}" = --help ]; then
  usage
  exit 0
fi
[ "$#" -le 1 ] || { usage >&2; exit 2; }
command -v git >/dev/null
command -v jq >/dev/null
command -v kata >/dev/null
kata_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd -P)
workspace=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)
runs="$workspace/.tracker/runs"
board_id=${1:-}
if [ -z "$board_id" ]; then
  # The board rewrites its ledger after every child, so the newest ledger belongs to the latest board run.
  newest=
  for ledger in "$runs"/*/board/state.json; do
    [ -f "$ledger" ] || continue
    if [ -z "$newest" ] || [ -n "$(find "$ledger" -newer "$newest")" ]; then
      newest=$ledger
    fi
  done
  [ -n "$newest" ] || { printf 'no board run found under %s\n' "$runs" >&2; exit 1; }
  board_id=$(basename "$(dirname "$(dirname "$newest")")")
fi
case "$board_id" in ''|*/*|.|..) printf 'invalid board run id: %s\n' "$board_id" >&2; exit 2 ;; esac
ledger="$runs/$board_id/board/state.json"
[ -f "$ledger" ] || { printf 'no board ledger at %s\n' "$ledger" >&2; exit 1; }
jq -e '(.finished | type == "boolean") and (.runs | type == "array") and
  all(.runs[]; (.run_id | type == "string" and length > 0) and
    (.kind == "completed" or .kind == "failed" or .kind == "empty"))' "$ledger" >/dev/null ||
  { printf 'invalid board ledger: %s\n' "$ledger" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
kata list --workspace "$workspace" --status open --limit 0 --json >"$tmp/open.json"
jq -e '.issues | type == "array"' "$tmp/open.json" >/dev/null || { printf 'invalid open-board response\n' >&2; exit 1; }

# One item per ledger entry, in ledger order. Empty attempts carry no kata.
: >"$tmp/items.jsonl"
jq -c '.runs[]' "$ledger" >"$tmp/runs.jsonl"
while IFS= read -r entry; do
  kind=$(printf '%s' "$entry" | jq -r '.kind')
  run_id=$(printf '%s' "$entry" | jq -r '.run_id')
  case "$run_id" in *[!a-f0-9]*) printf 'invalid child run id %s in %s\n' "$run_id" "$ledger" >&2; exit 1 ;; esac
  child="$runs/$run_id"
  case "$kind" in
    completed)
      qualified=$(jq -er '.qualified_id' "$child/selected.json" 2>/dev/null) ||
        { printf 'completed child %s has no selection record: %s\n' "$run_id" "$child/selected.json" >&2; exit 1; }
      printf '%s' "$entry" | jq -c --arg qualified "$qualified" '{group:"completed",qualified_id:$qualified,issue_uid,run_id,branch,
        base_commit:null,wip_commit:null,pr_url:(if .pr_url == "" then null else .pr_url end),
        reason:null,question:null,owner:null,labels:[],next:[]}' >>"$tmp/items.jsonl"
      ;;
    failed)
      [ -f "$child/handoff.json" ] ||
        { printf 'failed child %s has no handoff record: %s\n' "$run_id" "$child/handoff.json" >&2; exit 1; }
      jq -c --arg answer "$kata_dir/answer" '
        (if .reason == "decision" then "needs_decision" else "needs_review" end) as $group |
        {group:$group,qualified_id,issue_uid,run_id,branch,base_commit,wip_commit,pr_url:null,reason,question,owner:null,labels:[],
         next:(if $group == "needs_decision" then ["\($answer) \(.qualified_id) \"<your answer>\""]
               else ["git diff \(.base_commit)..\(.branch)", "\($answer) \(.qualified_id) \"<guidance>\""] end)}' \
        "$child/handoff.json" >>"$tmp/items.jsonl"
      ;;
    empty) ;;
  esac
done <"$tmp/runs.jsonl"

jq -n --arg board "$board_id" --arg workspace "$workspace" \
  --slurpfile state "$ledger" --slurpfile listing "$tmp/open.json" --slurpfile entries "$tmp/items.jsonl" '
  $state[0] as $ledger | $listing[0].issues as $issues |
  ($ledger.runs | map(.issue_uid // empty)) as $touched |
  # Handed-off katas are still open: show their live owner and labels beside the handoff record.
  ($entries | map(. as $item | ($issues | map(select(.uid == $item.issue_uid)) | first) as $live |
    if $item.group == "completed" then $item
    else $item + {owner:($live.owner // null), labels:($live.labels // [])} end)) as $items |
  {board_run_id:$board, workspace:$workspace, finished:$ledger.finished, stop_reason:($ledger.stop_reason // null),
   completed:[$items[] | select(.group == "completed")],
   needs_decision:[$items[] | select(.group == "needs_decision")],
   needs_review:[$items[] | select(.group == "needs_review")],
   remaining:[$issues[] | select(.uid as $uid | any($touched[]; . == $uid) | not) |
     {qualified_id, issue_uid:.uid, run_id:null, branch:null, base_commit:null, wip_commit:null, pr_url:null,
      reason:null, question:null, owner:(.owner // null), labels:(.labels // []), next:[]}]}
  | (.completed, .needs_decision, .needs_review) |= map(del(.group))
' >"$tmp/report.json"

if [ "$format" = json ]; then
  cat "$tmp/report.json"
  exit 0
fi
jq -r '
  def reason_text: . as $reason |
    {decision:"needs a decision", publish:"publication failed", review:"review rejected",
     turn_limit:"turn limit reached twice", implement:"worker stopped",
     unexpected_checkout:"handoff found the wrong branch"} | .[$reason] // $reason;
  def short: if . == null then "none" else .[0:8] end;
  def next_lines: .next[] | "      \(.)";
  "Board \(.board_run_id) in \(.workspace): \(if .stop_reason != null then "stopped" elif .finished then "finished" else "in progress" end)",
  "Completed (\(.completed | length))",
  (.completed[] | "  \(.qualified_id)  \(.branch)  \(.pr_url // "no pull request")"),
  "Needs decision (\(.needs_decision | length))",
  (.needs_decision[] | "  \(.qualified_id)  Q: \((.question // "") | gsub("\n"; " "))", next_lines),
  "Needs review (\(.needs_review | length))",
  (.needs_review[] | "  \(.qualified_id)  \(.reason | reason_text); branch \(.branch) (base \(.base_commit | short), wip \(.wip_commit | short)); run \(.run_id)", next_lines),
  "Remaining open (\(.remaining | length))",
  (.remaining[] | "  \(.qualified_id)  owned by \(.owner // "nobody")\(if (.labels | length) > 0 then ", labels \(.labels | join(","))" else "" end)"),
  (if .stop_reason != null then "Stop reason: \(.stop_reason)" else empty end)
' "$tmp/report.json"
```

Then `chmod +x kata/board-report`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `sh kata/tests/report.sh`
Expected: four `ok - ...` lines, exit 0. If the `diff -u` shows a difference in the `Q:` line, check the `gsub` call before anything else: the question in `handoff.json` contains a real newline.

- [ ] **Step 5: Wire the test and shellcheck into `kata/check`**

After the line `sh "$KATA_DIR/tests/answer.sh"` add:

```sh
sh "$KATA_DIR/tests/report.sh"
```

Change the shellcheck line to:

```sh
shellcheck "$KATA_DIR/check" "$KATA_DIR/retry-implementation" "$KATA_DIR/board-report" "$KATA_DIR/answer" "$KATA_DIR"/scripts/*.sh "$KATA_DIR"/tests/*.sh
```

- [ ] **Step 6: Run the full check and commit**

Run: `./kata/check` (expected: all green). Then:

```sh
git status
git add kata/board-report kata/tests/report.sh kata/check
git commit -m "feat(kata): add board-report for the morning review"
```

---

### Task 7: The board records clean failures and keeps claiming

**Files:**
- Modify: `kata/scripts/run-board.sh` (full replacement in Step 3)
- Modify: `kata/tests/board.sh` (full replacement in Step 1)
- Modify: `kata/board.dip:2,4`

**Interfaces:**
- Consumes: `<run>/handoff.json` from Task 3 (`run_id`, `issue_uid`, `reason`, `label`, `branch`, `start_branch`); the `handoff-ok` line that Task 3's handoff prints, which Tracker stores in `<run>/Handoff/status.json` at `.context_updates.tool_stdout` (verified with tracker 0.73.1: a failed tool node keeps its stdout there); `kata/board-report <board-run-id>` from Task 6, resolved as `$(dirname "$0")/../board-report`; `kata show <uid> --json` (`.issue.uid`, `.issue.status`, `.issue.owner`); `kata list --status open --limit 0 --json`.
- Produces: ledger entries `{run_id, kind:"failed", issue_uid, branch, reason, label}` beside the existing `completed` and `empty` kinds; an optional top-level `stop_reason` string (`"child <run-id> needs inspection"` or `"three consecutive failed children"`), deleted at the start of every controller iteration; `finished: true` at the end of the queue even when untouched open katas remain (`board/blocked.json` lists them); exit 0 at the end of the queue and exit 1 on every early stop. Task 6's report reads the ledger; Task 8's README describes this behavior.

Fixture design: the board test runs the real `run-board.sh` against real Tracker child runs of a tool-only workflow. The child workflow's `Handoff` node runs the real `kata/scripts/handoff-selected.sh` (Task 3), so the failure path under test is the production one. `CloseSelected` has no failure edge on purpose: a closure failure produces the integrity stop that the recovery cases need. The `kata` on PATH is a fixture that serves records from the disposable repository and logs every call.

- [ ] **Step 1: Replace the board test**

Write `kata/tests/board.sh` with exactly this content:

```sh
#!/bin/sh
# ABOUTME: Checks board orchestration with real Tracker child runs and disposable Git repositories.
# ABOUTME: Uses a local Kata CLI fixture; never claims real issues or contacts model providers.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
for required in scripts/run-board.sh scripts/handoff-selected.sh board-report board.dip; do
  [ -f "$pipeline_dir/$required" ] || {
    printf 'FAIL: %s is missing\n' "$required" >&2
    exit 1
  }
done

test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
mkdir -p "$test_root/bin" "$test_root/workflow/scripts"

cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
# ABOUTME: Supplies board records from a disposable repository and records handoff labels and comments.
# ABOUTME: Rejects unexpected commands so no real Kata daemon can be contacted.
set -eu
verb=$1
shift
action=
if [ "$verb" = label ]; then
  action=$1
  shift
fi
[ "$1" = --workspace ] || exit 91
workspace=$2
shift 2
actor=
if [ "${1:-}" = --as ]; then
  actor=$2
  shift 2
fi
fixture="$workspace/.tracker/board-fixture"
printf '%s %s\n' "$verb${action:+ $action}${actor:+ $actor}" "$*" >>"$fixture/kata.log"
case "$verb" in
  show)
    [ "$#" -eq 2 ] && [ "$2" = --json ] && [ -f "$fixture/$1.status" ] || exit 92
    owner=$(cat "$fixture/$1.owner" 2>/dev/null || true)
    jq -n --arg uid "$1" --arg status "$(cat "$fixture/$1.status")" --arg owner "$owner" \
      '{issue:{uid:$uid,status:$status,owner:(if $owner == "" then null else $owner end)}}'
    ;;
  list)
    [ "$*" = '--status open --limit 0 --json' ] || exit 93
    if [ -f "$fixture/blocked" ]; then
      printf '%s\n' '{"issues":[{"uid":"blocked-item","qualified_id":"blocked-item","status":"open","owner":"another-actor","labels":null}]}'
    else
      printf '%s\n' '{"issues":[]}'
    fi
    ;;
  label)
    [ "$action" = add ] && [ "$#" -eq 3 ] && [ "$3" = --agent ] || exit 95
    printf '%s\n' "$2" >>"$fixture/$1.labels"
    ;;
  comment)
    [ "$#" -eq 4 ] && [ "$2" = --body-file ] && [ "$4" = --agent ] || exit 96
    cp "$3" "$fixture/$1.comment"
    ;;
  *) printf 'unexpected fixture kata command: %s\n' "$verb" >&2; exit 94 ;;
esac
SH
chmod +x "$test_root/bin/kata"
export PATH="$test_root/bin:$PATH"
cat >"$test_root/workflow/complete.dip" <<'DIP'
# ABOUTME: Exercises board child identity, fail-forward handoffs, and artifacts without model nodes.
# ABOUTME: Performs real local commits and records a disposable issue lifecycle.
workflow BoardFixture
  goal: "Exercise real child orchestration"
  start: ClaimNext
  exit: Exit

  tool ClaimNext
    marker_grep: "^(claim-ok|queue-empty)$"
    command_file: claim.sh

  tool Implement
    command_file: implement.sh

  tool CloseSelected
    marker_grep: "^close-ok$"
    command_file: close.sh

  tool Handoff
    command_file: handoff.sh

  tool Exit
    command:
      true

  edges
    ClaimNext -> Implement  on claim-ok
    ClaimNext -> Exit  on queue-empty
    Implement -> CloseSelected  when ctx.outcome = success
    Implement -> Handoff  when ctx.outcome = fail
    CloseSelected -> Exit  when ctx.outcome = success
    Handoff -> Exit
DIP
cat >"$test_root/workflow/claim.sh" <<'SH'
#!/bin/sh
# ABOUTME: Creates the next local fixture task and records its actual child identity.
# ABOUTME: Checks the board's stack-base input against the checked-out Git history.
set -eu
cd "$TRACKER_WORKDIR"
mkdir -p "$TRACKER_RUN_DIR"
fixture="$TRACKER_WORKDIR/.tracker/board-fixture"
printf '%s\n' "$TRACKER_RUN_ID" >>"$fixture/claims"
remaining=$(cat "$fixture/remaining")
if [ "$remaining" -eq 0 ]; then
  printf 'queue-empty\n'
  exit 0
fi
number=$(wc -l <"$fixture/claims" | tr -d ' ')
uid="fixture-item-$number"
actor="kata-pipeline-$TRACKER_RUN_ID"
base=$(git rev-parse HEAD)
start_branch=$(git branch --show-current)
base_branch=main
# Only verified completions move the stack tip, so a stack base appears after the first closure.
if [ ! -s "$fixture/completed" ]; then
  [ -z "${KATA_STACK_BASE_FILE:-}" ] || {
    printf 'child before any completion unexpectedly received a stack base\n' >&2; exit 31;
  }
else
  [ -n "${KATA_STACK_BASE_FILE:-}" ] || {
    printf 'child after a completion did not receive a stack base\n' >&2; exit 32;
  }
  jq -e --arg base "$base" --arg branch "$start_branch" \
    '.commit == $base and .branch == $branch and .github.repository == "fixture/board"' \
    "$KATA_STACK_BASE_FILE" >/dev/null
  cp "$KATA_STACK_BASE_FILE" "$fixture/stack-$number.json"
  base_branch=$(jq -r '.branch' "$KATA_STACK_BASE_FILE")
fi
branch="kata/item-$number"
git switch -qc "$branch"
printf 'task %s\n' "$number" >"task-$number.txt"
git add "task-$number.txt"
git commit -qm "test: complete fixture task $number"
head=$(git rev-parse HEAD)
jq -n --arg workspace "$TRACKER_WORKDIR" --arg uid "$uid" --arg actor "$actor" --arg branch "$branch" \
  --arg base "$base" --arg start "$start_branch" --arg base_branch "$base_branch" \
  '{workspace:$workspace,issue_uid:$uid,short_id:$uid,qualified_id:("fixture#" + $uid),actor:$actor,
    branch:$branch,base_commit:$base,start_branch:$start,
    github:{remote:"origin",repository:"fixture/board",base_branch:$base_branch}}' \
  >"$TRACKER_RUN_DIR/selected.json"
printf '%s\n' "$head" >"$TRACKER_RUN_DIR/review-correctness.approved"
printf '%s\n' "$head" >"$TRACKER_RUN_DIR/review-scope.approved"
printf 'https://github.com/fixture/board/pull/%s\n' "$number" >"$TRACKER_RUN_DIR/pr-url.txt"
printf 'open\n' >"$fixture/$uid.status"
printf '%s\n' "$actor" >"$fixture/$uid.owner"
printf 'claim-ok\n'
SH
cat >"$test_root/workflow/implement.sh" <<'SH'
#!/bin/sh
# ABOUTME: Stands in for the worker: succeeds unless the fixture lists this attempt as a failure.
# ABOUTME: A failing attempt leaves uncommitted work behind for the real handoff to commit.
set -eu
cd "$TRACKER_WORKDIR"
fixture="$TRACKER_WORKDIR/.tracker/board-fixture"
number=$(wc -l <"$fixture/claims" | tr -d ' ')
if [ -f "$fixture/fail-implement" ] && grep -qx "$number" "$fixture/fail-implement"; then
  printf 'partial work %s\n' "$number" >"wip-$number.txt"
  remaining=$(cat "$fixture/remaining")
  printf '%s\n' "$((remaining - 1))" >"$fixture/remaining"
  printf 'deliberate fixture worker failure\n' >&2
  exit 34
fi
SH
cat >"$test_root/workflow/close.sh" <<'SH'
#!/bin/sh
# ABOUTME: Records a fixture closure after optional deliberate failure.
# ABOUTME: Leaves selected state intact so a real Tracker resume can complete it.
set -eu
fixture="$TRACKER_WORKDIR/.tracker/board-fixture"
if [ -f "$fixture/fail-close" ]; then
  printf 'deliberate fixture close failure\n' >&2
  exit 33
fi
uid=$(jq -r '.issue_uid' "$TRACKER_RUN_DIR/selected.json")
printf 'closed\n' >"$fixture/$uid.status"
printf '%s\n' "$uid" >>"$fixture/completed"
remaining=$(cat "$fixture/remaining")
printf '%s\n' "$((remaining - 1))" >"$fixture/remaining"
printf 'close-ok\n'
SH
# The handoff under test is the production script. The parent workflow resolves its
# controller and report beside itself, so the nested cases get copies of both.
cp "$pipeline_dir/scripts/handoff-selected.sh" "$test_root/workflow/handoff.sh"
cp "$pipeline_dir/board.dip" "$test_root/workflow/board.dip"
cp "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/scripts/run-board.sh"
cp "$pipeline_dir/board-report" "$test_root/workflow/board-report"
chmod +x "$test_root/workflow/board-report"

new_case() {
  repo="$test_root/$1 repository"
  git init -q -b main "$repo"
  repo=$(cd "$repo" && pwd -P)
  git -C "$repo" config user.name 'Board integration'
  git -C "$repo" config user.email 'board-check@example.invalid'
  git -C "$repo" config commit.gpgsign false
  printf '.tracker/\n' >"$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit -qm 'test: seed board repository'
  fixture="$repo/.tracker/board-fixture"
  mkdir -p "$fixture"
  printf '%s\n' "$2" >"$fixture/remaining"
  : >"$fixture/claims"
  : >"$fixture/completed"
  export TRACKER_WORKDIR="$repo" TRACKER_RUN_ID=board-parent
  export TRACKER_RUN_DIR="$repo/.tracker/runs/$TRACKER_RUN_ID"
  mkdir -p "$TRACKER_RUN_DIR"
  ledger="$TRACKER_RUN_DIR/board/state.json"
}

run_board() {
  (cd "$repo" && sh "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/complete.dip") \
    >"$test_root/output" 2>&1
}

must_succeed() {
  if ! run_board; then
    printf 'FAIL: board did not complete %s\n' "$1" >&2
    cat "$test_root/output" >&2
    for child_log in "$TRACKER_RUN_DIR"/board/items/*/child.log; do
      [ ! -f "$child_log" ] || tail -n 12 "$child_log" >&2
    done
    for status in "$repo"/.tracker/runs/*/ClaimNext/status.json "$repo"/.tracker/runs/*/Handoff/status.json; do
      [ ! -f "$status" ] || cat "$status" >&2
    done
    exit 1
  fi
}

must_stop() {
  if run_board; then
    printf 'FAIL: board accepted %s\n' "$1" >&2
    exit 1
  fi
}

claim_count() {
  wc -l <"$fixture/claims" | tr -d ' '
}

# Integration coverage: Tracker and Git are real; the Kata boundary is a fixture.
new_case stacked 2
must_succeed 'two stacked tasks'
jq -e --arg workspace "$repo" --arg pipeline "$test_root/workflow/complete.dip" \
  '.workspace == $workspace and .pipeline == $pipeline and .finished == true and
    (has("stop_reason") | not) and
    [.runs[].kind] == ["completed","completed","empty"] and
    ([.runs[].run_id] | unique | length) == 3 and
    all(.runs[]; .run_id != "board-parent") and
    .runs[0].branch == "kata/item-1" and .runs[1].branch == "kata/item-2" and
    .runs[1].github.base_branch == .runs[0].branch' "$ledger" >/dev/null
[ "$(claim_count)" -eq 3 ]
[ "$(git -C "$repo" rev-list --count HEAD)" -eq 3 ]
first_commit=$(jq -r '.runs[0].commit' "$ledger")
[ "$(git -C "$repo" rev-parse HEAD^)" = "$first_commit" ]
jq -e --arg commit "$first_commit" '.branch == "kata/item-1" and .commit == $commit' \
  "$fixture/stack-2.json" >/dev/null
for slot in 000001 000002 000003; do
  [ -s "$TRACKER_RUN_DIR/board/items/$slot/child.log" ]
done
jq -r '.runs[].run_id' "$ledger" | while IFS= read -r child; do
  [ -f "$repo/.tracker/runs/$child/activity.jsonl" ]
  jq -e '.outcome == "success"' "$repo/.tracker/runs/$child/Exit/status.json" >/dev/null
done
grep -F 'Board complete: 2 katas finished, 0 left open for review.' "$test_root/output" >/dev/null
grep -Fx 'Completed (2)' "$test_root/output" >/dev/null
grep -Fx '  fixture#fixture-item-2  kata/item-2  https://github.com/fixture/board/pull/2' "$test_root/output" >/dev/null
cp "$ledger" "$test_root/completed-ledger.json"
must_succeed 'already-finished parent resume'
cmp "$ledger" "$test_root/completed-ledger.json"
[ "$(claim_count)" -eq 3 ]
printf 'ok - real Tracker children use distinct IDs and stack commits without duplicate parent resume\n'

new_case empty 0
must_succeed 'initially empty board'
jq -e '.finished == true and (has("stop_reason") | not) and [.runs[].kind] == ["empty"]' "$ledger" >/dev/null
[ "$(claim_count)" -eq 1 ]
grep -F 'list --status open --limit 0 --json' "$fixture/kata.log" >/dev/null
grep -F 'Board complete: 0 katas finished, 0 left open for review.' "$test_root/output" >/dev/null
printf 'ok - an empty board requires the full open-issue query\n'

new_case failing 2
printf '1\n' >"$fixture/fail-implement"
must_succeed 'a failed first kata followed by a completed one'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["failed","completed","empty"] and
  .runs[0].issue_uid == "fixture-item-1" and .runs[0].branch == "kata/item-1" and
  .runs[0].reason == "implement" and .runs[0].label == "needs-review" and
  .runs[1].branch == "kata/item-2" and .runs[1].github.base_branch == "main"' "$ledger" >/dev/null
[ "$(claim_count)" -eq 3 ]
failed_child=$(head -n 1 "$fixture/claims")
main_commit=$(git -C "$repo" rev-parse main)
wip_commit=$(git -C "$repo" rev-parse kata/item-1)
jq -e --arg child "$failed_child" --arg wip "$wip_commit" \
  '.run_id == $child and .start_branch == "main" and .wip_commit == $wip and
    .reason == "implement" and .question == null' "$repo/.tracker/runs/$failed_child/handoff.json" >/dev/null
[ "$(git -C "$repo" log -1 --format=%s kata/item-1)" = "wip(kata): fixture#fixture-item-1 handoff from run $failed_child" ]
git -C "$repo" show --stat --format= kata/item-1 | grep -F 'wip-1.txt' >/dev/null
[ "$(git -C "$repo" branch --show-current)" = kata/item-2 ]
[ "$(git -C "$repo" rev-parse kata/item-2^)" = "$main_commit" ]
[ "$(cat "$fixture/fixture-item-1.status")" = open ]
[ "$(cat "$fixture/fixture-item-1.labels")" = needs-review ]
grep -Fx "label add kata-pipeline-$failed_child fixture-item-1 needs-review --agent" "$fixture/kata.log" >/dev/null
grep -F "Branch: kata/item-1 (base $main_commit, wip $wip_commit)" "$fixture/fixture-item-1.comment" >/dev/null
[ ! -e "$fixture/stack-2.json" ]
grep -Fx 'Failed fixture-item-1 (implement); left open with needs-review on kata/item-1' "$test_root/output" >/dev/null
grep -F 'Board complete: 1 katas finished, 1 left open for review.' "$test_root/output" >/dev/null
grep -Fx 'Completed (1)' "$test_root/output" >/dev/null
grep -Fx 'Needs review (1)' "$test_root/output" >/dev/null
grep -F '  fixture#fixture-item-1  worker stopped; branch kata/item-1' "$test_root/output" >/dev/null
printf 'ok - a clean worker failure is handed off and the next kata starts from the same base\n'

new_case stacked-failure 2
printf '2\n' >"$fixture/fail-implement"
must_succeed 'a completed kata followed by a failed one'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["completed","failed","empty"] and .runs[1].branch == "kata/item-2"' "$ledger" >/dev/null
[ "$(claim_count)" -eq 3 ]
failed_child=$(sed -n '2p' "$fixture/claims")
jq -e '.start_branch == "kata/item-1"' "$repo/.tracker/runs/$failed_child/handoff.json" >/dev/null
first_commit=$(jq -r '.runs[0].commit' "$ledger")
[ "$(git -C "$repo" branch --show-current)" = kata/item-1 ]
[ "$(git -C "$repo" rev-parse HEAD)" = "$first_commit" ]
[ "$(git -C "$repo" rev-parse kata/item-2~2)" = "$first_commit" ]
jq -e --arg commit "$first_commit" '.branch == "kata/item-1" and .commit == $commit' \
  "$fixture/stack-2.json" >/dev/null
grep -F 'Board complete: 1 katas finished, 1 left open for review.' "$test_root/output" >/dev/null
printf 'ok - a failure after a completion restores the stack tip and keeps the completed base\n'

new_case three-failures 4
printf '1\n2\n3\n' >"$fixture/fail-implement"
must_stop 'three consecutive failed children'
jq -e '.finished == false and .stop_reason == "three consecutive failed children" and
  [.runs[].kind] == ["failed","failed","failed"]' "$ledger" >/dev/null
[ "$(claim_count)" -eq 3 ]
[ "$(git -C "$repo" branch --show-current)" = main ]
grep -F 'Board stopped after three consecutive failed children' "$test_root/output" >/dev/null
grep -Fx 'Needs review (3)' "$test_root/output" >/dev/null
grep -Fx 'Stop reason: three consecutive failed children' "$test_root/output" >/dev/null
must_succeed 'parent resume after the failure streak'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["failed","failed","failed","completed","empty"]' "$ledger" >/dev/null
[ "$(claim_count)" -eq 5 ]
printf 'ok - three consecutive failures stop the board and a parent resume claims again\n'

new_case blocked 0
: >"$fixture/blocked"
must_succeed 'a queue with only owned or blocked katas'
jq -e '.finished == true and (has("stop_reason") | not) and [.runs[].kind] == ["empty"]' "$ledger" >/dev/null
[ "$(claim_count)" -eq 1 ]
jq -e '.issues[0].uid == "blocked-item"' "$TRACKER_RUN_DIR/board/blocked.json" >/dev/null
grep -F 'Board incomplete: 1 open katas remain, but none were ready and unowned.' "$test_root/output" >/dev/null
grep -Fx 'Remaining open (1)' "$test_root/output" >/dev/null
grep -Fx '  blocked-item  owned by another-actor' "$test_root/output" >/dev/null
printf 'ok - a blocked queue finishes the board and lists the untouched katas\n'

new_case recovery 1
: >"$fixture/fail-close"
must_stop 'failed child'
[ "$(claim_count)" -eq 1 ]
failed_child=$(head -n 1 "$fixture/claims")
jq -e --arg child "$failed_child" '.finished == false and .runs == [] and
  .stop_reason == "child \($child) needs inspection"' "$ledger" >/dev/null
jq -e '.outcome == "fail"' "$repo/.tracker/runs/$failed_child/CloseSelected/status.json" >/dev/null
[ ! -e "$repo/.tracker/runs/$failed_child/handoff.json" ]
grep -F "Child run $failed_child needs inspection" "$test_root/output" >/dev/null
must_stop 'unrecovered child on parent resume'
[ "$(claim_count)" -eq 1 ]
rm "$fixture/fail-close"
if ! tracker --git off --workdir "$repo" --json --no-tui --resume "$failed_child" \
  "$test_root/workflow/complete.dip" >"$test_root/recovery.log" 2>&1; then
  printf 'FAIL: real Tracker child resume failed\n' >&2
  cat "$test_root/recovery.log" >&2
  exit 1
fi
[ "$(claim_count)" -eq 1 ]
child_dir="$repo/.tracker/runs/$failed_child"
cp "$child_dir/review-scope.approved" "$test_root/scope.approved"
printf 'stale approval\n' >"$child_dir/review-scope.approved"
must_stop 'stale approval after child recovery'
cp "$test_root/scope.approved" "$child_dir/review-scope.approved"
printf 'unfinished work\n' >"$repo/uncommitted.txt"
must_stop 'dirty tree after child recovery'
rm "$repo/uncommitted.txt"
git -C "$repo" switch -q main
must_stop 'changed branch after child recovery'
git -C "$repo" switch -q kata/item-1
printf 'open\n' >"$fixture/fixture-item-1.status"
must_stop 'unclosed issue after child recovery'
printf 'closed\n' >"$fixture/fixture-item-1.status"
cp "$child_dir/CloseSelected/status.json" "$test_root/close-status.json"
jq '.context_updates.tool_marker="claim-ok"' "$test_root/close-status.json" \
  >"$child_dir/CloseSelected/status.json"
must_stop 'missing closure marker after child recovery'
cp "$test_root/close-status.json" "$child_dir/CloseSelected/status.json"
[ "$(claim_count)" -eq 1 ]
must_succeed 'manually recovered child'
jq -e --arg child "$failed_child" \
  '.finished == true and (has("stop_reason") | not) and
    [.runs[].kind] == ["completed","empty"] and .runs[0].run_id == $child' "$ledger" >/dev/null
[ "$(claim_count)" -eq 2 ]
[ "$(git -C "$repo" rev-list --count HEAD)" -eq 2 ]
must_succeed 'completed recovered parent resume'
[ "$(claim_count)" -eq 2 ]
printf 'ok - an integrity stop halts claims; a real child resume reconciles once without duplicate work\n'

# Invoke the actual parent workflow so nested tool environments and failure routing are real.
new_case nested 1
if ! tracker --git off --workdir "$repo" --json --no-tui "$test_root/workflow/board.dip" \
  >"$test_root/parent.log" 2>&1; then
  printf 'FAIL: real Tracker parent did not complete its child workflow\n' >&2
  tail -n 20 "$test_root/parent.log" >&2
  exit 1
fi
parent_id=$(jq -Rnr '[inputs | fromjson? | select(.source == "pipeline" and .type == "pipeline_started")][0].run_id' \
  <"$test_root/parent.log")
parent_ledger="$repo/.tracker/runs/$parent_id/board/state.json"
jq -e --arg parent "$parent_id" '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["completed","empty"] and all(.runs[]; .run_id != $parent)' "$parent_ledger" >/dev/null
[ "$(claim_count)" -eq 2 ]
new_case nested-failure 1
: >"$fixture/fail-close"
if tracker --git off --workdir "$repo" --json --no-tui "$test_root/workflow/board.dip" \
  >"$test_root/parent-failure.log" 2>&1; then
  printf 'FAIL: real Tracker parent hid a child integrity stop\n' >&2
  tail -n 20 "$test_root/parent-failure.log" >&2
  exit 1
fi
[ "$(claim_count)" -eq 1 ]
parent_id=$(jq -Rnr '[inputs | fromjson? | select(.source == "pipeline" and .type == "pipeline_started")][0].run_id' \
  <"$test_root/parent-failure.log")
jq -e '.finished == false and (.stop_reason | startswith("child "))' \
  "$repo/.tracker/runs/$parent_id/board/state.json" >/dev/null
printf 'ok - real Tracker parent isolates child identity and reports a child integrity stop as failure\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh kata/tests/board.sh; printf 'exit %s\n' "$?"`
Expected: `exit 1` with no `ok` line. The `stacked` case's first failing assertion is the grep for `Board complete: 2 katas finished, 0 left open for review.`: the current controller prints `Board complete: 2 katas finished. Ledger: ...` and never calls the report. To see which line stopped the script, run `sh -x kata/tests/board.sh 2>&1 | tail -n 5`.

- [ ] **Step 3: Replace the controller**

Write `kata/scripts/run-board.sh` with exactly this content:

```sh
#!/bin/sh
# ABOUTME: Runs complete.dip once per kata with a durable ledger of isolated child runs.
# ABOUTME: Carries verified stack bases forward, records clean failures for review, and stops on integrity problems.
set -eu

if [ "${1:-}" = --help ]; then
  printf 'Usage: run-board.sh /path/to/complete.dip\nInvoked by board.dip with Tracker run identity. Logs and ledger are in the parent run directory under board/.\n'
  exit 0
fi
[ "$#" -eq 1 ] && [ -f "$1" ] || { printf 'expected the complete.dip source path\n' >&2; exit 1; }
: "${TRACKER_RUN_DIR:?TRACKER_RUN_DIR is required}"
: "${TRACKER_RUN_ID:?TRACKER_RUN_ID is required}"
: "${TRACKER_WORKDIR:?TRACKER_WORKDIR is required}"
command -v tracker >/dev/null
command -v kata >/dev/null
command -v jq >/dev/null
report=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)/board-report
[ -x "$report" ] || { printf 'board report is missing or not executable: %s\n' "$report" >&2; exit 1; }
workspace=$(cd "$TRACKER_WORKDIR" && pwd -P)
pipeline=$(CDPATH='' cd -- "$(dirname "$1")" && printf '%s/%s' "$(pwd -P)" "$(basename "$1")")
cd "$workspace"
[ "$(git rev-parse --show-toplevel)" = "$workspace" ] || { printf 'target is not the Git root\n' >&2; exit 1; }
board="$TRACKER_RUN_DIR/board"
mkdir -p "$board/items"
lock="$board/lock"
if ! mkdir "$lock" 2>/dev/null; then
  owner=$(cat "$lock/pid" 2>/dev/null || true)
  case "$owner" in ''|*[!0-9]*) printf 'board lock has no valid owner; inspect %s\n' "$lock" >&2; exit 1 ;; esac
  if kill -0 "$owner" 2>/dev/null; then
    printf 'board controller is already running (PID %s)\n' "$owner" >&2
    exit 1
  fi
  rm "$lock/pid"
  rmdir "$lock"
  mkdir "$lock"
fi
printf '%s\n' "$$" >"$lock/pid"
child_pid=
trap 'rm -f "$lock/pid"; rmdir "$lock"' EXIT
trap 'if [ -n "$child_pid" ]; then kill "$child_pid" 2>/dev/null || true; wait "$child_pid" 2>/dev/null || true; fi; exit 130' HUP INT TERM
state="$board/state.json"
if [ ! -e "$state" ]; then
  jq -n --arg workspace "$workspace" --arg pipeline "$pipeline" \
    '{workspace:$workspace,pipeline:$pipeline,runs:[],finished:false}' >"$state.tmp"
  mv "$state.tmp" "$state"
fi
jq -e --arg workspace "$workspace" --arg pipeline "$pipeline" '
  .workspace == $workspace and .pipeline == $pipeline and
  (.finished | type == "boolean") and (.runs | type == "array") and
  (.stop_reason == null or (.stop_reason | type == "string")) and
  all(.runs[]; (.run_id | type == "string" and test("^[a-f0-9]{12}$")) and
    (.kind == "completed" or .kind == "failed" or .kind == "empty")) and
  ([.runs[].run_id] | length == (unique | length))
' "$state" >/dev/null || { printf 'invalid board state or changed workspace/pipeline: %s\n' "$state" >&2; exit 1; }

write_state() {
  jq "$@" "$state" >"$state.tmp"
  mv "$state.tmp" "$state"
}
set_stop_reason() {
  write_state --arg reason "$1" '.stop_reason = $reason'
}
stop_child() {
  set_stop_reason "child $run_id needs inspection"
  printf 'Child run %s needs inspection; no next kata was started.\nLogs: %s\n' "$run_id" "$item/child.log" >&2
  printf 'Recover the child in %s with tracker -r %s %s, then resume board %s.\n' "$workspace" "$run_id" "$pipeline" "$TRACKER_RUN_ID" >&2
  exit 1
}
append_run() {
  write_state --argjson result "$result" '.runs += [$result]'
}
# A clean failure left the kata open, labeled, and commented, and put the checkout back on the
# branch the child started from. Anything else is an integrity problem and stops the board.
record_failure() {
  handoff="$child/handoff.json"
  jq -e --arg run "$run_id" '.run_id == $run and
    all(.issue_uid, .reason, .label, .branch, .start_branch; type == "string" and length > 0)' \
    "$handoff" >/dev/null 2>&1 || stop_child
  jq -e '.context_updates.tool_stdout | type == "string" and (split("\n") | any(. == "handoff-ok"))' \
    "$child/Handoff/status.json" >/dev/null 2>&1 || stop_child
  [ "$(git symbolic-ref --quiet --short HEAD)" = "$(jq -r '.start_branch' "$handoff")" ] || stop_child
  [ -z "$(git status --porcelain --untracked-files=normal)" ] || stop_child
  if [ -n "$KATA_STACK_BASE_FILE" ]; then
    [ "$(git rev-parse HEAD)" = "$(jq -r '.commit' "$KATA_STACK_BASE_FILE")" ] || stop_child
  fi
  uid=$(jq -r '.issue_uid' "$handoff")
  issue=$(kata show --workspace "$workspace" "$uid" --json)
  printf '%s' "$issue" | jq -e --arg uid "$uid" --arg actor "kata-pipeline-$run_id" \
    '.issue.uid == $uid and .issue.status == "open" and .issue.owner == $actor' >/dev/null || stop_child
  result=$(jq --arg run "$run_id" '{run_id:$run,kind:"failed",issue_uid,branch,reason,label}' "$handoff")
  append_run
  printf 'Failed %s (%s); left open with %s on %s\n' "$uid" \
    "$(jq -r '.reason' "$handoff")" "$(jq -r '.label' "$handoff")" "$(jq -r '.branch' "$handoff")"
  if jq -e '[.runs[-3:][].kind] == ["failed","failed","failed"]' "$state" >/dev/null; then
    set_stop_reason 'three consecutive failed children'
    printf 'Board stopped after three consecutive failed children. Ledger: %s\n' "$state" >&2
    "$report" "$TRACKER_RUN_ID"
    exit 1
  fi
}

while ! jq -e '.finished' "$state" >/dev/null; do
  # A stop reason describes the previous controller's last iteration; this one decides afresh.
  write_state 'del(.stop_reason)'
  index=$(jq '.runs | length + 1' "$state")
  item="$board/items/$(printf '%06d' "$index")"
  mkdir -p "$item"
  # Empty and failed attempts do not change the stack tip. Only verified child completions do.
  jq '[.runs[] | select(.kind == "completed")] | last' "$state" >"$item/base.json"
  KATA_STACK_BASE_FILE=
  if jq -e '. != null' "$item/base.json" >/dev/null; then
    KATA_STACK_BASE_FILE="$item/base.json"
  fi
  export KATA_STACK_BASE_FILE
  if [ ! -e "$item/child.log" ]; then
    printf 'Starting kata attempt %s; child output: %s\n' "$index" "$item/child.log"
    # Create the log before launch. An interrupted launch must never silently claim twice.
    : >"$item/child.log"
    tracker --git off --json --no-tui --workdir "$workspace" "$pipeline" >"$item/child.log" 2>&1 &
    child_pid=$!
    printf '%s\n' "$child_pid" >"$item/child.pid"
    wait "$child_pid" || true
    child_pid=
    rm "$item/child.pid"
  elif [ -f "$item/child.pid" ]; then
    pending_pid=$(cat "$item/child.pid")
    case "$pending_pid" in ''|*[!0-9]*) printf 'invalid child PID; inspect %s\n' "$item" >&2; exit 1 ;; esac
    if kill -0 "$pending_pid" 2>/dev/null; then
      printf 'child process %s is still running; wait before resuming the board\n' "$pending_pid" >&2
      exit 1
    fi
  fi
  run_id=$(jq -Rnr '[inputs | fromjson? | select(.source == "pipeline" and .type == "pipeline_started") | .run_id] | unique | if length == 1 then .[0] else empty end' <"$item/child.log")
  case "$run_id" in ''|*[!a-f0-9]*) printf 'child identity is unknown; inspect %s before retrying\n' "$item/child.log" >&2; exit 1 ;; esac
  [ "${#run_id}" -eq 12 ] || { printf 'invalid child run ID\n' >&2; exit 1; }
  child="$workspace/.tracker/runs/$run_id"
  # The child's activity log includes manual resumes; the initial CLI log does not.
  [ -f "$child/activity.jsonl" ] || stop_child
  terminal=$(jq -Rnr --arg run "$run_id" '[inputs | fromjson? |
    select(.source == "pipeline" and .run_id == $run and
      (.type == "pipeline_started" or .type == "pipeline_completed" or .type == "pipeline_failed"))] |
    last | if .type == "pipeline_completed" and .terminal_status == "success" then "completed"
      elif .type == "pipeline_failed" then "failed" else "unknown" end' <"$child/activity.jsonl")
  if [ "$terminal" = failed ]; then
    record_failure
    continue
  fi
  [ "$terminal" = completed ] || stop_child
  jq -e '.outcome == "success"' "$child/Exit/status.json" >/dev/null 2>&1 || stop_child
  if [ -f "$child/selected.json" ]; then
    selected="$child/selected.json"
    jq -e --arg workspace "$workspace" '.workspace == $workspace and
      (.issue_uid | type == "string" and length > 0) and has("github")' "$selected" >/dev/null || stop_child
    jq -e '.outcome == "success" and .context_updates.tool_marker == "close-ok"' \
      "$child/CloseSelected/status.json" >/dev/null 2>&1 || stop_child
    uid=$(jq -r '.issue_uid' "$selected")
    branch=$(jq -er '.branch' "$selected")
    head=$(git rev-parse HEAD)
    [ "$(git symbolic-ref --quiet --short HEAD)" = "$branch" ] || stop_child
    [ -z "$(git status --porcelain --untracked-files=normal)" ] || stop_child
    for approval in review-correctness.approved review-scope.approved; do
      [ "$(sed -n '1p' "$child/$approval" 2>/dev/null || true)" = "$head" ] || stop_child
    done
    issue=$(kata show --workspace "$workspace" "$uid" --json)
    printf '%s' "$issue" | jq -e --arg uid "$uid" '.issue.uid == $uid and .issue.status == "closed"' >/dev/null || stop_child
    if jq -e --arg uid "$uid" 'any(.runs[]; .kind == "completed" and .issue_uid == $uid)' "$state" >/dev/null; then
      printf 'child repeated an already completed kata: %s\n' "$uid" >&2
      exit 1
    fi
    pr_url=
    if jq -e '.github != null' "$selected" >/dev/null; then
      [ -s "$child/pr-url.txt" ] || stop_child
      pr_url=$(cat "$child/pr-url.txt")
    fi
    result=$(jq --arg run "$run_id" --arg head "$head" --arg url "$pr_url" \
      '{run_id:$run,kind:"completed",issue_uid,branch,commit:$head,github,pr_url:$url}' "$selected")
    append_run
    printf 'Completed %s on %s%s\n' "$uid" "$branch" "${pr_url:+; $pr_url}"
  else
    jq -e '.outcome == "success" and .context_updates.tool_marker == "queue-empty"' \
      "$child/ClaimNext/status.json" >/dev/null 2>&1 || stop_child
    open=$(kata list --workspace "$workspace" --status open --limit 0 --json)
    printf '%s' "$open" | jq -e '.issues | type == "array"' >/dev/null || { printf 'invalid open-board response\n' >&2; exit 1; }
    # Katas this board handed off stay open on purpose; only untouched ones count as remaining.
    remaining=$(printf '%s' "$open" | jq --slurpfile state "$state" \
      '[.issues[] | select(.uid as $uid | any($state[0].runs[]; .issue_uid == $uid) | not)] | length')
    result=$(jq -n --arg run "$run_id" '{run_id:$run,kind:"empty"}')
    append_run
    if [ "$remaining" -gt 0 ]; then
      printf '%s\n' "$open" >"$board/blocked.json"
      printf 'Board incomplete: %s open katas remain, but none were ready and unowned. See %s\n' "$remaining" "$board/blocked.json"
    fi
    write_state '.finished = true'
  fi
done
printf 'Board complete: %s katas finished, %s left open for review. Ledger: %s\n' \
  "$(jq '[.runs[] | select(.kind == "completed")] | length' "$state")" \
  "$(jq '[.runs[] | select(.kind == "failed")] | length' "$state")" "$state"
"$report" "$TRACKER_RUN_ID"
```

- [ ] **Step 4: Update the parent workflow's description**

In `kata/board.dip`, replace line 2 with:

```
# ABOUTME: Stacks reviewed task branches and PRs and records failures for the morning review.
```

and replace line 4 with:

```
  goal: "Complete all ready unowned katas sequentially with stacked PRs, leaving unfinished work open for the morning review."
```

The node definitions and the `RunBoard -> Exit` edge stay as they are: a controller exit 1 still fails the parent run.

- [ ] **Step 5: Run the test and the validators**

Run: `sh kata/tests/board.sh; printf 'exit %s\n' "$?"`
Expected: eight `ok - ...` lines in this order, then `exit 0`:

```
ok - real Tracker children use distinct IDs and stack commits without duplicate parent resume
ok - an empty board requires the full open-issue query
ok - a clean worker failure is handed off and the next kata starts from the same base
ok - a failure after a completion restores the stack tip and keeps the completed base
ok - three consecutive failures stop the board and a parent resume claims again
ok - a blocked queue finishes the board and lists the untouched katas
ok - an integrity stop halts claims; a real child resume reconciles once without duplicate work
ok - real Tracker parent isolates child identity and reports a child integrity stop as failure
```

If a `must_succeed` case fails, the test prints the controller output, the last 12 lines of every child log, and every child's `ClaimNext` and `Handoff` status record to stderr; read those before changing anything. A `Child run <id> needs inspection` line in the `failing` case means `record_failure` rejected the handoff: compare the printed `Handoff/status.json` (`.context_updates.tool_stdout` must contain `handoff-ok`, `.context_updates.tool_stderr` shows the handoff's own error) against the checks in `record_failure`. A silent `exit 1` after several `ok` lines means an assertion in the next case failed; `sh -x kata/tests/board.sh 2>&1 | tail -n 5` shows the command.

Then run:

```sh
shellcheck kata/scripts/run-board.sh kata/tests/board.sh
dippin check --format json kata/board.dip | jq -e '.valid and .errors == 0'
tracker validate kata/board.dip
```

Expected: no ShellCheck output, `true`, and the tracker validator's known warning about unset runtime context variables (the same output `kata/check` reports today).

- [ ] **Step 6: Run the full check and commit**

Run: `./kata/check` (expected: all green, exit 0). Then:

```sh
git status
git add kata/scripts/run-board.sh kata/tests/board.sh kata/board.dip
git commit -m "feat(kata): keep the board going after clean failures and report them"
```

---

### Task 8: Prompt and README describe the overnight board and the morning review

**Files:**
- Modify: `kata/prompts/implement.md` (insert after the resume paragraph)
- Modify: `kata/README.md` (four edits, anchored on exact text)
- Modify: `gotchas.md` (append one entry)

**Interfaces:**
- Consumes: the behavior built in Tasks 1–7: `ContinueImplement` (450-turn warm continue after an `operator_decision` breach), `question.md` → `needs-decision`, the handoff comment's `Branch: <branch> (base <sha>, wip <sha or none>)` line, `kata/board-report`, `kata/answer`, the ledger's `failed` entries and `stop_reason`, exit 0 at the end of the queue.
- Produces: documentation only. Task 9 removes the retry section from the same README and rewrites two `gotchas.md` paragraphs; the anchors below do not overlap with Task 9's.

- [ ] **Step 1: Extend the implementation prompt**

In `kata/prompts/implement.md`, find the paragraph that ends with this line:

```
the conflict in the handoff and stop rather than committing it.
```

Insert these three paragraphs directly after it, each separated by a blank line:

```
When finishing this item needs a decision only a person can make, write the exact
question to `question.md` in the same directory as `STATE_PATH`, keep `handoff.md`
current, and finish with `STATUS: fail`. The pipeline then labels the kata `needs-decision`
and a person answers it in a comment.

When the issue's comments record an earlier pipeline attempt, that comment names its
branch and base commit. Diff that branch against its base and reuse what is correct.
Do not switch to it.

This step may run again after a turn limit with a larger budget and the earlier
episode summary. Continue from the current diff; do not repeat discovery or restart
the plan.
```

- [ ] **Step 2: Update the README's review and turn-limit paragraphs**

In `kata/README.md`, replace these two lines:

```
Both must approve publication and closure. Rejected work gets at most one repair pass and
another review. Unfinished work stays open with a `needs-review` handoff.
```

with:

```
Both must approve publication and closure. Rejected work gets at most one repair pass and
another review. A worker that hits its turn limit while still making progress gets one
automatic continue. Unfinished work stays open, labeled `needs-review` or `needs-decision`,
for the morning review.
```

Then find this line:

```
The larger ceilings preserve the same one-item scope and single repair pass.
```

and insert this paragraph after it, separated by a blank line:

```
`Implement` gets one automatic warm continue. When it stops at its turn limit while
still making steady progress (tracker's `operator_decision` breach class), the pipeline
raises its ceiling to 450 turns and restarts the worker once with its earlier episode
summary. A second breach hands the kata off.
```

- [ ] **Step 3: Replace the board's failure paragraphs**

In `kata/README.md`, replace the two paragraphs that start with `The board stops on its first failed child.` and `The parent run's `board/state.json` records child IDs, commits, and PR URLs.` (they end with the line `Keep the checkout on the last task branch with a clean working tree.`) with:

```
A child that fails cleanly does not stop the board. The handoff labels the kata
`needs-review` (or `needs-decision` when the worker wrote a question), comments
the branch and base commit, commits any uncommitted work as a WIP commit on the
task branch, and returns the checkout to the branch the child started on. The
board records the failure in its ledger and claims the next kata from the same
stack base, so a failed kata never becomes the base of a later one. Three
consecutive failed children stop the board with `stop_reason` set in the ledger.
If no item is ready and unowned, the board checks all open items: katas it
already handed off are expected, and any other open kata is listed in
`board/blocked.json` and counted in the `Board incomplete` line. The board then
finishes; the report lists those katas under `Remaining open`. It never takes
another actor's claim. Parents become eligible as their children close. The
runner rechecks the live board after each child, so newly added eligible work
is included. The controller exits 0 at the end of the queue and 1 on every
early stop, and it prints the morning review either way.

The parent run's `board/state.json` records every child: `completed` entries
carry the commit and PR URL, `failed` entries carry the branch, reason, and
label, and `empty` entries mark an empty queue. Each child's console output is
under `board/items/<attempt>/child.log`; full artifacts remain in the target
repository's `.tracker/runs/<child-id>`. A stop with `child <child-id> needs
inspection` means the child ended in a state the controller could not verify:
a failed closure, a dirty tree, an unexpected branch, or a handoff that did not
complete. Inspect and recover that child using the one-item recovery guidance
below, then resume the parent with
`tracker --no-tui -r <board-run-id> /path/to/kata/board.dip`.
A child killed with its parent (a closed TUI or Ctrl-C) still owns its kata as
`kata-pipeline-<child-id>`. Resume that child from the target repository with
`tracker -r <child-id> /path/to/kata/complete.dip` before resuming the board.
The controller verifies the existing child's outcome before advancing, so
resuming the parent does not silently claim a replacement item. A board stopped
by three consecutive failures can be resumed; it claims again from the same
stack base. A finished board is not resumed; start a new board run after
answering or unblocking its katas. Keep the checkout on the last task branch
with a clean working tree. Runs claimed before the handoff recorded a starting
branch stop for inspection at handoff.
```

- [ ] **Step 4: Add the morning review section**

In `kata/README.md`, insert this section directly before the line `## Check`:

````
## Morning review

Katas the board could not finish stay open, owned by `kata-pipeline-<child-id>`,
with a `needs-review` or `needs-decision` label and a comment naming the branch,
base commit, WIP commit, and question. This section is written for the agent or
person working that inbox. From the target Git root:

```sh
/path/to/pipelines/kata/board-report
```

prints the newest board run: completed katas with branches and PR URLs, katas
that need a decision with their questions, katas that need review with their
branches, and open katas the board never touched. `board-report --json
<board-run-id>` prints the same for one run as JSON.

For each kata that needs a decision, read the question and answer it:

```sh
/path/to/pipelines/kata/answer <issue-ref> "<your answer>"
```

For each kata that needs review, diff the WIP branch against its base commit
and read the review records under the child run directory
(`.tracker/runs/<child-id>/Review*/status.json` and `ReReview*/status.json`).
Either finish and close it by hand, or answer with guidance so the next run
can finish it. Merge the PR stack oldest first. Then run the board again in
the evening with the same command as before.

`kata/answer` comments the text on the kata and releases the pipeline's claim,
so the next board run can claim it. It refuses katas owned by anyone other than
a pipeline actor. The label stays until the next claim removes it. The next run
reads the comment thread and reuses the branch's work. Both commands run from
the target Git root and change nothing else.

````

- [ ] **Step 5: Mention the new tests in the Check section**

In `kata/README.md`, find this line in the `## Check` section:

```
or live GitHub publication. Stack-base tests verify the fetched predecessor SHA.
```

and replace it with:

```
or live GitHub publication. Stack-base tests verify the fetched predecessor SHA.
Board tests also run the real handoff script inside child runs. Continue tests
drive a real tracker restart; handoff, answer, and report tests use fixture Kata
records and run directories.
```

- [ ] **Step 6: Record the decision in `gotchas.md`**

Append this entry to the end of `gotchas.md`, after a blank line:

```
Doctor Biz chose fail-forward boards with a morning review (2026-09-16): a failed
child hands its kata off (label, comment, WIP commit, starting branch restored)
and the board claims the next one; three consecutive failures stop it. A queue
with only owned or blocked katas finishes the board. `kata/board-report`
summarizes a board run and `kata/answer` comments a reply and releases the
pipeline claim. Implement gets one automatic warm continue (450 turns) after a
steady turn-limit breach; the second breach hands off.
```

- [ ] **Step 7: Verify and commit**

Run: `./kata/check` (expected: all green, exit 0; the README table of turn ceilings is unchanged, so `kata/tests/check.sh` still passes). Read the three edited files once top to bottom for leftover references to stopping on the first failure. Then:

```sh
git status
git add kata/prompts/implement.md kata/README.md gotchas.md
git commit -m "docs(kata): describe the overnight board and morning review"
```

---

### Task 9: Retire `retry-implementation`

**Files:**
- Delete: `kata/retry-implementation`, `kata/tests/retry-implementation.sh`
- Modify: `kata/check:37-38` (the test call and the shellcheck argument)
- Modify: `kata/README.md` (remove the retry section)
- Modify: `gotchas.md` (rewrite two paragraphs)

**Interfaces:**
- Consumes: nothing new. `ContinueImplement` (Task 1) and `kata/answer` (Task 5) cover the cases the manual rewind handled.
- Produces: nothing references `retry-implementation` except the historical note in `kata/PLAN.md:86`, which stays.

- [ ] **Step 1: Verify the current references**

Run:

```sh
git grep -n 'retry-implementation' -- . ':!docs/superpowers'
```

Expected hits: `gotchas.md` (two paragraphs), `kata/PLAN.md:86`, `kata/README.md` (the retry section), `kata/check` (two lines), and `kata/tests/retry-implementation.sh` itself. Anything else is a reference this task must also remove.

- [ ] **Step 2: Delete the command and its test**

```sh
git rm kata/retry-implementation kata/tests/retry-implementation.sh
```

- [ ] **Step 3: Remove the lines from `kata/check`**

Delete this line:

```sh
"$KATA_DIR/tests/retry-implementation.sh"
```

and change the shellcheck line from:

```sh
shellcheck "$KATA_DIR/check" "$KATA_DIR/retry-implementation" "$KATA_DIR/board-report" "$KATA_DIR/answer" "$KATA_DIR"/scripts/*.sh "$KATA_DIR"/tests/*.sh
```

to:

```sh
shellcheck "$KATA_DIR/check" "$KATA_DIR/board-report" "$KATA_DIR/answer" "$KATA_DIR"/scripts/*.sh "$KATA_DIR"/tests/*.sh
```

- [ ] **Step 4: Remove the README section**

In `kata/README.md`, delete the paragraph that starts with `If `Implement` exhausted its turns and the run reached `Handoff`, stop tracker`, the code block that follows it (`/path/to/pipelines/kata/retry-implementation "<run-id>"`), and the paragraph after that code block that starts with `This command verifies the saved workspace, branch, base commit, and live issue` and ends with `reviews; later failures need inspection rather than restarting the whole review cycle.` Keep the paragraph that follows (`For tracker v0.73.1, `-r` reads ...`).

- [ ] **Step 5: Rewrite the two `gotchas.md` paragraphs**

Replace this paragraph:

```
Tracker resume continues at the saved node, including a terminal Handoff.
After an implementation turn-limit failure, use kata/retry-implementation to
back up and rewind only the failed worker state while retaining its claim.
Check the repository-local checkpoint: tracker v0.73.1 can write fresh logs
under ~/.local/state/tracker while leaving a stale checkpoint copy there.
```

with:

```
Tracker resume continues at the saved node, including a terminal Handoff. An
implementation turn-limit breach with steady progress gets one automatic warm
continue inside the pipeline (ContinueImplement); a second breach hands the kata
off for the morning review, so there is no manual rewind command. Check the
repository-local checkpoint: tracker v0.73.1 can write fresh logs under
~/.local/state/tracker while leaving a stale checkpoint copy there.
```

Replace this paragraph:

```
kata scripts resolve every path physically (`pwd -P`), so a test that compares
a path against script output must resolve its own path the same way. On this
machine `~/workspace` is a symlink to `~/Public/src`, and the agent shell's cwd
is the symlinked form: `kata/tests/retry-implementation.sh` computed its
pipeline_dir with logical `pwd`, grepped that path in the resume hint, missed,
and `set -e` exited 1 with no message, so `kata/check` went red silently. The
same test passed when invoked by its physical path. Fixed with `pwd -P` on
2026-09-15.
```

with:

```
kata scripts resolve every path physically (`pwd -P`), so a test that compares
a path against script output must resolve its own path the same way. On this
machine `~/workspace` is a symlink to `~/Public/src`, and the agent shell's cwd
is the symlinked form: a kata test once computed its pipeline_dir with logical
`pwd`, grepped that path in a script's output, missed, and `set -e` exited 1
with no message, so `kata/check` went red silently. The same test passed when
invoked by its physical path. Every kata test now uses `pwd -P` (since
2026-09-15).
```

- [ ] **Step 6: Verify and commit**

Run:

```sh
git grep -n 'retry-implementation' -- . ':!docs/superpowers'
./kata/check
```

Expected: the only hit is `kata/PLAN.md:86`; the check is green with exit 0. Then:

```sh
git status
git add kata/check kata/README.md gotchas.md
git commit -m "chore(kata): retire retry-implementation"
```

(`git rm` already staged the two deletions.)

---

### Task 10: Final verification

**Files:** none changed unless a check fails.

**Interfaces:**
- Consumes: everything above.
- Produces: a green `./kata/check`, a clean tree, and a report to Doctor Biz.

- [ ] **Step 1: Run the canonical check from a clean tree**

```sh
git status
./kata/check; printf 'exit %s\n' "$?"
```

Expected: `git status` reports nothing to commit; the check prints every `ok - ...` line from the routes, continue, handoff, check, github-setup, approvals, preflight, close, publish, board, answer, and report tests, the tracker static-validation note, and `exit 0`.

- [ ] **Step 2: Confirm the commit series**

```sh
git log --oneline -9
```

Expected, newest first:

```
chore(kata): retire retry-implementation
docs(kata): describe the overnight board and morning review
feat(kata): keep the board going after clean failures and report them
feat(kata): add board-report for the morning review
feat(kata): add answer to reply to a handed-off kata and release its claim
feat(kata): clear the warm-continue override after closure
feat(kata): hand off failed katas with WIP, labels, and a handoff record
feat(kata): record the starting branch and clear handoff state at claim
feat(kata): grant one warm continue after a steady turn-limit breach
```

If a subject differs from the one its task specified, leave the history alone and mention it in the final report.

- [ ] **Step 3: Live board on a scratch repository (Doctor Biz's call)**

The automated tests cannot prove a model finishes a kata. The live check needs a scratch Git repository that already has kata initialized and two small katas on its board, plus Lunaroute credentials in the shell or in `~/.config/tracker/.env`. Do not create practice katas to probe kata, and do not touch the `mux` or `todo-test-2` workspaces; ask Doctor Biz for the scratch repository and its katas before running anything. Then, from that repository's Git root:

```sh
tracker --no-tui --workdir "$PWD" /path/to/pipelines/kata/board.dip
/path/to/pipelines/kata/board-report
```

Expected: the board runs both katas, the report lists them under `Completed` or `Needs review`/`Needs decision`, and any handed-off kata is open, owned by `kata-pipeline-<child-id>`, labeled, and commented. For a handed-off kata, answer it and confirm the release:

```sh
/path/to/pipelines/kata/answer <issue-ref> "Checked; continue from the branch."
```

Expected: `Owner: nobody` and the label still listed. Record the date and outcome as one line at the end of the fail-forward entry in `gotchas.md` and commit it as `docs(kata): record the live overnight board check`. Never print `~/.config/tracker/.env` values.

- [ ] **Step 4: Report**

Tell Doctor Biz: the commit list, the `./kata/check` result, whether the live check ran and what it showed, and any tracker or kata behavior that had to be worked around rather than fixed (those are flagged, not patched).

---
