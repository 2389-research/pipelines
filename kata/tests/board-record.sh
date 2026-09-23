#!/bin/sh
# ABOUTME: Checks board-record.sh: it classifies one board sweep from the subgraph body's workspace-root
# ABOUTME: records, appends a self-contained ledger entry, scrubs bookkeeping, rotates the run-id, and marks.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
record="$pipeline_dir/scripts/board-record.sh"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
command -v jq >/dev/null

KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"

# A fake kata that answers only show and list, each from a file the current case writes.
mkdir -p "$test_root/bin"
cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
set -eu
case "${1:-}" in
  show) [ -f "$KATA_SHOW" ] || { printf 'no show fixture\n' >&2; exit 91; }; cat "$KATA_SHOW" ;;
  list) [ -f "$KATA_LIST" ] || { printf 'no list fixture\n' >&2; exit 92; }; cat "$KATA_LIST" ;;
  *) printf 'unexpected fake kata call: %s\n' "$*" >&2; exit 90 ;;
esac
SH
chmod +x "$test_root/bin/kata"
PATH="$test_root/bin:$PATH"
export PATH
KATA_SHOW="$test_root/show.json"
KATA_LIST="$test_root/list.json"
export KATA_SHOW KATA_LIST

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/out" ] || { printf -- '--- stdout ---\n' >&2; cat "$test_root/out" >&2; }
  [ ! -f "$test_root/err" ] || { printf -- '--- stderr ---\n' >&2; cat "$test_root/err" >&2; }
  exit 1
}

count=0
# Builds a clean repo and runs board-preflight so the managed excludes, ledger, and run-id match
# production exactly. Leaves repo, ledger, exclude, runidfile, and the seeded run-id in this shell.
fresh() {
  count=$((count + 1))
  repo="$test_root/repo$count"
  git init -q -b main "$repo"
  repo=$(cd "$repo" && pwd -P)
  ( cd "$repo" && git commit -q --allow-empty -m root )
  run_id="board-parent-$count"
  run_dir="$repo/.tracker/runs/$run_id"
  export TRACKER_WORKDIR="$repo" TRACKER_RUN_DIR="$run_dir" TRACKER_RUN_ID="$run_id"
  sh "$pipeline_dir/scripts/board-preflight.sh" "$pipeline_dir" >/dev/null || fail "preflight failed in fresh()"
  ledger="$run_dir/board/state.json"
  exclude="$repo/.git/info/exclude"
  runidfile="$repo/.tracker/kata-board-run-id"
  seeded=$(cat "$runidfile")
}

node_status() { mkdir -p "$repo/$1"; printf '%s\n' "$2" >"$repo/$1/status.json"; }

run_record() {
  status=0
  sh "$record" "$pipeline_dir" >"$test_root/out" 2>"$test_root/err" || status=$?
}
marker() { tail -n 1 "$test_root/out"; }
last_run() { jq '.runs[-1]' "$ledger"; }
tree_clean() { [ -z "$(cd "$repo" && git status --porcelain --untracked-files=normal)" ]; }
has_block() { grep -Fx '# BEGIN kata board managed excludes' "$exclude" >/dev/null 2>&1; }

# --- completed: a landed kata records a completed entry and sweeps again ------
fresh
( cd "$repo" && git commit -q --allow-empty -m base && git commit -q --allow-empty -m landed )
base_commit=$(cd "$repo" && git rev-parse HEAD~1)
head=$(cd "$repo" && git rev-parse HEAD)
uid=01ARZ3NDEKTSV4RRFFQ69G5FAV
branch="kata/5fav-$seeded"
cat >"$repo/selected.json" <<JSON
{"issue_uid":"$uid","short_id":"5fav","qualified_id":"demo#5fav","workspace":"$repo","branch":"$branch","base_commit":"$base_commit","actor":"kata-pipeline-$seeded","trunk":"main","issue":{}}
JSON
node_status ClaimNext '{"outcome":"success","context_updates":{"tool_marker":"claim-ok"}}'
node_status CloseSelected '{"outcome":"success","context_updates":{"tool_marker":"close-ok"}}'
node_status Exit '{"outcome":"success","context_updates":{}}'
printf '%s\n' "$head" >"$repo/review-correctness.approved"
printf '%s\n' "$head" >"$repo/review-scope.approved"
printf 'ran the suite\n' >"$repo/verification.txt"
printf 'did the thing thoroughly enough to satisfy the length gate here\n' >"$repo/completion.md"
printf '{"issue":{"uid":"%s","status":"closed","owner":"kata-pipeline-%s"}}\n' "$uid" "$seeded" >"$KATA_SHOW"
run_record
[ "$status" -eq 0 ] || fail "completed exited $status"
[ "$(marker)" = sweep-again ] || fail "completed marker is $(marker), expected sweep-again"
last_run | jq -e --arg run "$seeded" --arg uid "$uid" --arg b "$branch" --arg base "$base_commit" --arg head "$head" '
  .kind == "completed" and .run_id == $run and .issue_uid == $uid and .qualified_id == "demo#5fav" and
  .branch == $b and .base_commit == $base and .commit == $head' >/dev/null || { last_run >&2; fail "completed entry is wrong"; }
grep -F 'Landed demo#5fav' "$test_root/out" >/dev/null || fail 'completed did not print a Landed line'
[ ! -e "$repo/selected.json" ] || fail 'completed did not scrub selected.json'
[ ! -e "$repo/CloseSelected" ] || fail 'completed did not scrub the CloseSelected node dir'
[ ! -e "$repo/Exit" ] || fail 'completed did not scrub the Exit node dir'
[ ! -e "$repo/review-correctness.approved" ] || fail 'completed did not scrub an approval'
has_block || fail 'completed removed the managed excludes on a sweep-again'
[ "$(cat "$runidfile")" != "$seeded" ] || fail 'completed did not rotate the run-id'
case "$(cat "$runidfile")" in "$run_id"-??????) ;; *) fail "rotated run-id lost its parent prefix: $(cat "$runidfile")" ;; esac
[ "$(cd "$repo" && git rev-parse HEAD)" = "$head" ] || fail 'completed moved HEAD'
[ "$(cd "$repo" && git symbolic-ref --quiet --short HEAD)" = main ] || fail 'completed left the trunk'
tree_clean || fail 'completed left the working tree dirty'
printf 'ok - a landed kata is recorded, scrubbed, and sweeps again on a fresh run-id\n'

# --- completed integrity: a surviving task branch is an inspection stop -------
fresh
( cd "$repo" && git commit -q --allow-empty -m base && git commit -q --allow-empty -m landed )
base_commit=$(cd "$repo" && git rev-parse HEAD~1)
head=$(cd "$repo" && git rev-parse HEAD)
branch="kata/5fav-$seeded"
( cd "$repo" && git branch "$branch" )
cat >"$repo/selected.json" <<JSON
{"issue_uid":"$uid","short_id":"5fav","qualified_id":"demo#5fav","workspace":"$repo","branch":"$branch","base_commit":"$base_commit","actor":"kata-pipeline-$seeded","trunk":"main","issue":{}}
JSON
node_status CloseSelected '{"outcome":"success","context_updates":{"tool_marker":"close-ok"}}'
node_status Exit '{"outcome":"success","context_updates":{}}'
printf '%s\n' "$head" >"$repo/review-correctness.approved"
printf '%s\n' "$head" >"$repo/review-scope.approved"
printf '{"issue":{"uid":"%s","status":"closed"}}\n' "$uid" >"$KATA_SHOW"
run_record
[ "$status" -eq 0 ] || fail "surviving-branch exited $status"
[ "$(marker)" = board-needs-human ] || fail "surviving-branch marker is $(marker)"
jq -e '.runs == [] and (.stop_reason | type == "string")' "$ledger" >/dev/null || fail 'surviving-branch recorded a run or lost the stop reason'
has_block && fail 'surviving-branch kept the managed excludes on a terminal stop'
[ "$(cd "$repo" && git rev-parse --quiet --verify "refs/heads/$branch")" != "" ] || fail 'surviving-branch scrub deleted the git branch'
printf 'ok - a surviving task branch after close holds the board for a person\n'

# --- failed: a handoff records a failed entry and sweeps past it --------------
fresh
branch="kata/bq4e-$seeded"
cat >"$repo/selected.json" <<JSON
{"issue_uid":"$uid","short_id":"bq4e","qualified_id":"demo#bq4e","workspace":"$repo","branch":"$branch","base_commit":"1234abcd","actor":"kata-pipeline-$seeded","trunk":"main","issue":{}}
JSON
cat >"$repo/handoff.json" <<JSON
{"run_id":"$seeded","issue_uid":"$uid","qualified_id":"demo#bq4e","reason":"review","label":"needs-review","branch":"$branch","base_commit":"1234abcd","wip_commit":"5678ef01","trunk":"main","question":null}
JSON
node_status Handoff '{"outcome":"fail","context_updates":{"tool_stdout":"handoff-ok\n"}}'
node_status Exit '{"outcome":"success","context_updates":{}}'
printf '{"issue":{"uid":"%s","status":"open","owner":"kata-pipeline-%s"}}\n' "$uid" "$seeded" >"$KATA_SHOW"
run_record
[ "$status" -eq 0 ] || fail "failed exited $status"
[ "$(marker)" = sweep-again ] || fail "failed marker is $(marker), expected sweep-again"
last_run | jq -e --arg run "$seeded" --arg uid "$uid" --arg b "$branch" '
  .kind == "failed" and .run_id == $run and .issue_uid == $uid and .qualified_id == "demo#bq4e" and
  .branch == $b and .reason == "review" and .label == "needs-review" and .base_commit == "1234abcd" and
  .wip_commit == "5678ef01" and .trunk == "main" and .question == null' >/dev/null || { last_run >&2; fail 'failed entry is wrong'; }
grep -F 'Failed demo#bq4e' "$test_root/out" >/dev/null || fail 'failed did not print a Failed line'
[ ! -e "$repo/handoff.json" ] || fail 'failed did not scrub handoff.json'
[ ! -e "$repo/Handoff" ] || fail 'failed did not scrub the Handoff node dir'
has_block || fail 'failed removed the managed excludes on a sweep-again'
[ "$(cat "$runidfile")" != "$seeded" ] || fail 'failed did not rotate the run-id'
printf 'ok - a handoff is recorded and the board sweeps past it\n'

# --- failed integrity: an unexpected checkout holds for a person -------------
fresh
branch="kata/bq4e-$seeded"
cat >"$repo/handoff.json" <<JSON
{"run_id":"$seeded","issue_uid":"$uid","qualified_id":"demo#bq4e","reason":"unexpected_checkout","label":"needs-review","branch":"$branch","base_commit":"1234abcd","wip_commit":null,"trunk":"main","question":null}
JSON
node_status Handoff '{"outcome":"fail","context_updates":{"tool_stdout":"handoff-ok\n"}}'
node_status Exit '{"outcome":"success","context_updates":{}}'
run_record
[ "$status" -eq 0 ] || fail "unexpected-checkout exited $status"
[ "$(marker)" = board-needs-human ] || fail "unexpected-checkout marker is $(marker)"
jq -e '.runs == [] and (.stop_reason | test("checkout"))' "$ledger" >/dev/null || fail 'unexpected-checkout recorded a run or has no checkout stop reason'
has_block && fail 'unexpected-checkout kept the managed excludes on a terminal stop'
printf 'ok - an unexpected checkout is not recorded and holds the board\n'

# --- three consecutive failures stop the board ------------------------------
fresh
jq '.runs = [
  {"run_id":"board-parent-x-000001","kind":"failed","issue_uid":"01AAAAAAAAAAAAAAAAAAAAAAAA","branch":"kata/a-x","reason":"review","label":"needs-review"},
  {"run_id":"board-parent-x-000002","kind":"failed","issue_uid":"01BBBBBBBBBBBBBBBBBBBBBBBB","branch":"kata/b-x","reason":"review","label":"needs-review"}]' \
  "$ledger" >"$ledger.t" && mv "$ledger.t" "$ledger"
branch="kata/bq4e-$seeded"
cat >"$repo/handoff.json" <<JSON
{"run_id":"$seeded","issue_uid":"$uid","qualified_id":"demo#bq4e","reason":"review","label":"needs-review","branch":"$branch","base_commit":"1234abcd","wip_commit":null,"trunk":"main","question":null}
JSON
node_status Handoff '{"outcome":"fail","context_updates":{"tool_stdout":"handoff-ok\n"}}'
node_status Exit '{"outcome":"success","context_updates":{}}'
printf '{"issue":{"uid":"%s","status":"open","owner":"kata-pipeline-%s"}}\n' "$uid" "$seeded" >"$KATA_SHOW"
run_record
[ "$status" -eq 0 ] || fail "three-fail exited $status"
[ "$(marker)" = board-needs-human ] || fail "three-fail marker is $(marker)"
jq -e '(.runs | length) == 3 and (.runs[-1].kind == "failed") and (.stop_reason | test("three consecutive"))' \
  "$ledger" >/dev/null || fail 'three-fail did not record the third failure and stop reason'
has_block && fail 'three-fail kept the managed excludes on a terminal stop'
printf 'ok - three consecutive failed katas stop the board for a person\n'

# --- empty and clean: an exhausted queue with nothing to review is board-clean
fresh
node_status ClaimNext '{"outcome":"success","context_updates":{"tool_marker":"queue-empty"}}'
node_status Exit '{"outcome":"success","context_updates":{}}'
printf '{"issues":[]}\n' >"$KATA_LIST"
run_record
[ "$status" -eq 0 ] || fail "empty-clean exited $status"
[ "$(marker)" = board-clean ] || fail "empty-clean marker is $(marker), expected board-clean"
jq -e '.finished == true and (.runs[-1].kind == "empty")' "$ledger" >/dev/null || fail 'empty-clean did not finish with an empty entry'
has_block && fail 'empty-clean kept the managed excludes on a terminal outcome'
[ "$(cat "$runidfile")" = "$seeded" ] || fail 'empty-clean rotated the run-id on a terminal outcome'
[ ! -e "$repo/ClaimNext" ] || fail 'empty-clean did not scrub the ClaimNext node dir'
printf 'ok - an empty queue with nothing open for review is board-clean\n'

# --- empty with an open handoff to review is board-needs-human ---------------
fresh
jq '.runs = [
  {"run_id":"board-parent-y-000001","kind":"failed","issue_uid":"01CCCCCCCCCCCCCCCCCCCCCCCC","branch":"kata/c-y","reason":"review","label":"needs-review"}]' \
  "$ledger" >"$ledger.t" && mv "$ledger.t" "$ledger"
node_status ClaimNext '{"outcome":"success","context_updates":{"tool_marker":"queue-empty"}}'
node_status Exit '{"outcome":"success","context_updates":{}}'
printf '{"issues":[]}\n' >"$KATA_LIST"
run_record
[ "$status" -eq 0 ] || fail "empty-review exited $status"
[ "$(marker)" = board-needs-human ] || fail "empty-review marker is $(marker)"
jq -e '.finished == true and ([.runs[] | select(.kind=="empty")] | length) == 1' "$ledger" >/dev/null || fail 'empty-review did not append an empty entry'
printf 'ok - an empty queue with an open handoff needs a person\n'

# --- empty but katas remain untouched is board-needs-human + blocked.json ----
fresh
node_status ClaimNext '{"outcome":"success","context_updates":{"tool_marker":"queue-empty"}}'
node_status Exit '{"outcome":"success","context_updates":{}}'
printf '{"issues":[{"uid":"01ZZZZZZZZZZZZZZZZZZZZZZZZ","qualified_id":"demo#zz11","status":"open","owner":null,"labels":[]}]}\n' >"$KATA_LIST"
run_record
[ "$status" -eq 0 ] || fail "empty-remaining exited $status"
[ "$(marker)" = board-needs-human ] || fail "empty-remaining marker is $(marker)"
[ -f "$run_dir/board/blocked.json" ] || fail 'empty-remaining did not write blocked.json'
printf 'ok - an empty queue with untouched open katas needs a person and records the blockage\n'

# --- an unclassifiable sweep (a failed claim) holds for a person -------------
fresh
node_status ClaimNext '{"outcome":"fail","context_updates":{}}'
node_status Exit '{"outcome":"success","context_updates":{}}'
run_record
[ "$status" -eq 0 ] || fail "failed-claim exited $status"
[ "$(marker)" = board-needs-human ] || fail "failed-claim marker is $(marker)"
jq -e '.runs == [] and (.stop_reason | type == "string")' "$ledger" >/dev/null || fail 'failed-claim recorded a run or lost the stop reason'
printf 'ok - a claim that neither selected nor emptied the queue holds the board\n'

# --- the parent env is required ---------------------------------------------
fresh
node_status ClaimNext '{"outcome":"success","context_updates":{"tool_marker":"queue-empty"}}'
saved="$TRACKER_RUN_DIR"
unset TRACKER_RUN_DIR
run_record
[ "$status" -ne 0 ] || fail 'board-record passed with TRACKER_RUN_DIR unset'
[ -z "$(marker)" ] || grep -Eqv '^(sweep-again|board-clean|board-needs-human)$' "$test_root/out" || fail 'board-record printed a marker despite a missing env'
export TRACKER_RUN_DIR="$saved"
printf 'ok - board-record stops without a marker when the parent env is missing\n'

printf 'ok - board-record.sh\n'
