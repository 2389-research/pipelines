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
