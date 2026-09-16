#!/bin/sh
# ABOUTME: Exercises turn-limit checkpoint recovery using disposable real Git repositories.
# ABOUTME: Stubs only the read-only kata and process boundaries; never contacts the daemon.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
repo="$test_root/target repo"
run_id=9a3759fbecae
run_dir="$repo/.tracker/runs/$run_id"
mkdir -p "$run_dir/ClaimNext" "$run_dir/Implement" "$test_root/bin"
git init -q -b kata/retry "$repo"
git -C "$repo" config user.name 'Pipeline check'
git -C "$repo" config user.email 'pipeline-check@example.invalid'
printf '.tracker/\n' >"$repo/.gitignore"
git -C "$repo" add .gitignore
git -C "$repo" commit -qm 'test: seed retry repository'
repo=$(cd "$repo" && pwd -P)
run_dir="$repo/.tracker/runs/$run_id"
base=$(git -C "$repo" rev-parse HEAD)
printf 'preserve incomplete work\n' >"$repo/unfinished.txt"
jq -n --arg workspace "$repo" --arg base "$base" \
  '{workspace:$workspace,base_commit:$base,branch:"kata/retry",issue_uid:"01ARZ3NDEKTSV4RRFFQ69G5FAV",actor:"kata-pipeline-9a3759fbecae"}' \
  >"$run_dir/selected.json"
cp "$run_dir/selected.json" "$test_root/selected.json"
cat >"$run_dir/checkpoint.json" <<'JSON'
{"run_id":"9a3759fbecae","current_node":"Handoff","completed_nodes":["ClaimNext","Implement"],"retry_counts":{"Implement":1},"context":{"graph.goal":"complete one kata","graph.pipeline_dir":"/original/pipeline","node.ClaimNext.tool_stdout":"","node.ClaimNext.outcome":"success","node.Implement.outcome":"fail","node.Implement.response":"stale failure","outcome":"fail","turn_limit_msg":"exhausted","turn_breach_class":"operator_decision","_summary.stale":"old summary"},"timestamp":"2026-09-13T12:00:00Z","restart_count":0,"edge_selections":{"ClaimNext":"Implement","Implement":"Handoff"},"gate_states":{"Implement":{"last_outcome":"fail"}}}
JSON
cp "$run_dir/checkpoint.json" "$test_root/original.json"
printf '%s\n' '{"outcome":"fail","context_updates":{"turn_limit_msg":"node Implement exhausted turn limit (30 turns)","turn_breach_class":"operator_decision"}}' >"$run_dir/Implement/status.json"
printf '%s\n' '{"outcome":"success","context_updates":{"tool_marker":"claim-ok","tool_stdout":"claim-ok\nSTATE_PATH=/old/path"}}' >"$run_dir/ClaimNext/status.json"
cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
set -eu
[ "$#" -eq 5 ] && [ "$1" = show ] && [ "$2" = --workspace ] && [ "$3" = "$PWD" ] && [ "$4" = 01ARZ3NDEKTSV4RRFFQ69G5FAV ] && [ "$5" = --json ] || exit 92
printf '%s\n' "$*" >>"$FAKE_KATA_LOG"
jq -n --arg owner "${FAKE_OWNER:-kata-pipeline-9a3759fbecae}" --arg status "${FAKE_STATUS:-open}" '{issue:{uid:"01ARZ3NDEKTSV4RRFFQ69G5FAV",owner:$owner,status:$status}}'
SH
cat >"$test_root/bin/pgrep" <<'SH'
#!/bin/sh
[ "$*" = '-x tracker' ] || exit 2
exit "${FAKE_TRACKER_EXIT:-1}"
SH
chmod +x "$test_root/bin/kata" "$test_root/bin/pgrep"
export PATH="$test_root/bin:$PATH" FAKE_KATA_LOG="$test_root/kata.log"
cd "$repo"
reject() {
  cp "$run_dir/checkpoint.json" "$test_root/before-refusal.json"
  if "$pipeline_dir/retry-implementation" "$run_id" >"$test_root/output" 2>&1; then
    printf 'FAIL: recovery accepted %s\n' "$1" >&2; exit 1
  fi
  if ! grep -F "$1" "$test_root/output" >/dev/null; then
    printf 'FAIL: wrong refusal for %s\n' "$1" >&2; cat "$test_root/output" >&2; exit 1
  fi
  cmp "$run_dir/checkpoint.json" "$test_root/before-refusal.json"
}
# A missing helper must fail as a missing behavior, before testing refusal paths.
if [ ! -x "$pipeline_dir/retry-implementation" ]; then
  printf 'FAIL: turn-limit recovery command is missing\n' >&2; exit 1
fi
"$pipeline_dir/retry-implementation" --help >"$test_root/output"
grep -F 'Usage:' "$test_root/output" >/dev/null
run_id='../escape'; reject 'invalid run ID'; run_id=9a3759fbecae
jq --arg workspace "$test_root" '.workspace=$workspace' "$test_root/selected.json" >"$run_dir/selected.json"
reject 'tracker workspace changed'
unrelated=$(printf 'Unrelated history\n' | git commit-tree "$(git mktree </dev/null)")
jq --arg base "$unrelated" '.base_commit=$base' "$test_root/selected.json" >"$run_dir/selected.json"
reject 'task history no longer descends'
cp "$test_root/selected.json" "$run_dir/selected.json"
FAKE_TRACKER_EXIT=0; export FAKE_TRACKER_EXIT; reject 'stop all tracker processes'; unset FAKE_TRACKER_EXIT
FAKE_TRACKER_EXIT=2; export FAKE_TRACKER_EXIT; reject 'cannot inspect tracker processes'; unset FAKE_TRACKER_EXIT
git switch -qc kata/other
reject 'task branch changed'
git switch -q kata/retry
FAKE_OWNER=another-actor; export FAKE_OWNER; reject 'no longer open and owned'; unset FAKE_OWNER
FAKE_STATUS=closed; export FAKE_STATUS; reject 'no longer open and owned'; unset FAKE_STATUS
for expression in '.current_node="Implement"' '.completed_nodes += ["ReviewCorrectness"]' '.run_id="different"' '.validation_overrides=[{}]' '.future_routing={}' '.gate_states.ReviewCorrectness={last_outcome:"success"}' '.retry_counts.Repair=1' '.node_outcomes.ReviewCorrectness="success"' '.memo_entries.review={status:"success"}'; do
  jq "$expression" "$test_root/original.json" >"$run_dir/checkpoint.json"
  reject 'checkpoint is not a first implementation handoff'
done
cp "$test_root/original.json" "$run_dir/checkpoint.json"
printf 'stale approval\n' >"$run_dir/review-scope.approved"
reject 'review or close artifacts already exist'
rm "$run_dir/review-scope.approved"
cp "$run_dir/Implement/status.json" "$test_root/implement.json"
printf '%s\n' '{"outcome":"fail","context_updates":{"turn_limit_msg":"other failure"}}' >"$run_dir/Implement/status.json"
reject 'not an operator-decision turn-limit failure'
cp "$test_root/implement.json" "$run_dir/Implement/status.json"
"$pipeline_dir/retry-implementation" "$run_id" >"$test_root/output" 2>&1 || { cat "$test_root/output" >&2; exit 1; }
jq -e --arg state "$run_dir/selected.json" \
  '.current_node == "Implement" and .completed_nodes == ["ClaimNext"] and
   .edge_selections == {ClaimNext:"Implement"} and .retry_counts == {} and .gate_states == {} and
   .context == {"graph.goal":"complete one kata","graph.pipeline_dir":"/original/pipeline",
     "node.ClaimNext.tool_stdout":("claim-ok\nSTATE_PATH=" + $state),
     "node.ClaimNext.tool_marker":"claim-ok","node.ClaimNext.outcome":"success"} and
   .run_id == "9a3759fbecae" and .timestamp == "2026-09-13T12:00:00Z"' "$run_dir/checkpoint.json" >/dev/null
set -- "$run_dir"/checkpoint.json.before-retry.*
[ "$#" -eq 1 ] && cmp "$1" "$test_root/original.json"
cmp "$run_dir/selected.json" "$test_root/selected.json"
[ "$(cat "$repo/unfinished.txt")" = 'preserve incomplete work' ]
[ "$(git rev-list --count HEAD)" = 1 ]
[ "$(git branch --show-current)" = kata/retry ]
grep -F "$pipeline_dir/complete.dip" "$test_root/output" >/dev/null
grep -F -- "-r $run_id" "$test_root/output" >/dev/null
reject 'checkpoint is not a first implementation handoff'
# A second preparation of the same original must never overwrite the first backup.
cp "$test_root/original.json" "$run_dir/checkpoint.json"
"$pipeline_dir/retry-implementation" "$run_id" >"$test_root/output" 2>&1
set -- "$run_dir"/checkpoint.json.before-retry.*
[ "$#" -eq 2 ]
for backup in "$@"; do cmp "$backup" "$test_root/original.json"; done
printf 'ok - implementation retry restores the claim, preserves work, and refuses unsafe recovery\n'
