#!/bin/sh
# ABOUTME: Checks kata/board-report against fixture ledgers, handoff records, and a fixture open-issue list.
# ABOUTME: Compares the text report exactly, checks the JSON shape, and proves unsafe records are refused.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
report="$pipeline_dir/board-report"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
command -v jq >/dev/null
# The report prints commands as ~/... under the operator's home; a fixture home keeps the expected text fixed.
HOME="$test_root/home"
mkdir -p "$HOME"
export HOME

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
  {"uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","status":"open","owner":"kata-pipeline-f1f1f1f1f1f1","labels":["needs-review","task"]},
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
short_base=$(printf '%.12s' "$base")
short_wip=$(printf '%.12s' "$wip")

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

selected() {
  mkdir -p "$runs/$1"
  printf '%s\n' "$2" >"$runs/$1/selected.json"
}

ledger older '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":false,"stop_reason":"three consecutive failed children","runs":[
  {"run_id":"b1b1b1b1b1b1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-b1b1b1b1b1b1","reason":"turn_limit","label":"needs-review"}]}'
touch -t 202001010000 "$runs/older/board/state.json"
ledger newer '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"c1c1c1c1c1c1","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-c1c1c1c1c1c1","commit":"'"$head"'","github":{"remote":"origin","repository":"o/r","base_branch":"main"},"pr_url":"https://github.com/o/r/pull/12"},
  {"run_id":"d1d1d1d1d1d1","kind":"failed","issue_uid":"01DECISION0000000000000000","branch":"kata/n4vr-d1d1d1d1d1d1","reason":"decision","label":"needs-decision"},
  {"run_id":"f1f1f1f1f1f1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-f1f1f1f1f1f1","reason":"review","label":"needs-review"},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"}]}'
selected c1c1c1c1c1c1 '{"issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav"}'
handoff d1d1d1d1d1d1 '{"run_id":"d1d1d1d1d1d1","issue_uid":"01DECISION0000000000000000","qualified_id":"demo#n4vr","reason":"decision","label":"needs-decision","branch":"kata/n4vr-d1d1d1d1d1d1","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":"Should the CLI accept --format=json\nas well as --json?"}'
handoff f1f1f1f1f1f1 '{"run_id":"f1f1f1f1f1f1","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"review","label":"needs-review","branch":"kata/bq4e-f1f1f1f1f1f1","base_commit":"'"$base"'","wip_commit":"'"$wip"'","start_branch":"main","question":null}'
handoff b1b1b1b1b1b1 '{"run_id":"b1b1b1b1b1b1","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"turn_limit","label":"needs-review","branch":"kata/bq4e-b1b1b1b1b1b1","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":null}'

# Tracker reflows the review at 76 columns: every line is short, no line depends on its indent,
# and every command is whole on one line with its path quoted.
cat >"$test_root/expected" <<EXPECTED
Board newer in $repo: finished
Completed (1)
- demo#5fav on kata/5fav-c1c1c1c1c1c1
  https://github.com/o/r/pull/12
Needs decision (1)
- demo#n4vr: needs a decision (run d1d1d1d1d1d1)
  branch kata/n4vr-d1d1d1d1d1d1, base $short_base, wip none
  Q: Should the CLI accept --format=json as well as --json?
  '$pipeline_dir/answer' demo#n4vr "<your answer>"
Needs review (1)
- demo#bq4e: review rejected (run f1f1f1f1f1f1)
  branch kata/bq4e-f1f1f1f1f1f1, base $short_base, wip $short_wip
  git diff $short_base..kata/bq4e-f1f1f1f1f1f1
  '$pipeline_dir/answer' demo#bq4e "<guidance>"
Remaining open (2)
- demo#a2j0 owned by kata-pipeline-b20d9e898b16
- demo#zz11 owned by nobody, labels task
EXPECTED
(cd "$repo" && "$report") >"$test_root/output" 2>&1 || fail 'report failed for the newest run'
diff -u "$test_root/expected" "$test_root/output" || fail 'text report differs from the expected output'
printf 'ok - the text report picks the newest board run and groups its katas\n'

(cd "$repo" && "$report" --json newer) >"$test_root/report.json" 2>"$test_root/output" || fail 'json report failed'
jq -e --arg repo "$repo" --arg answer "$pipeline_dir/answer" --arg base "$base" --arg wip "$wip" --arg short "$short_base" '
  .board_run_id == "newer" and .workspace == $repo and .pipeline == "/p/complete.dip" and .finished == true and
  .stop_reason == null and .stop_child == null and
  [.completed[].qualified_id] == ["demo#5fav"] and .completed[0].run_id == "c1c1c1c1c1c1" and
  .completed[0].pr_url == "https://github.com/o/r/pull/12" and .completed[0].next == [] and
  [.needs_decision[].qualified_id] == ["demo#n4vr"] and
  .needs_decision[0].question == "Should the CLI accept --format=json\nas well as --json?" and
  .needs_decision[0].owner == "kata-pipeline-d1d1d1d1d1d1" and .needs_decision[0].labels == ["needs-decision"] and
  .needs_decision[0].next == ["\($answer) demo#n4vr \"<your answer>\""] and
  [.needs_review[].qualified_id] == ["demo#bq4e"] and .needs_review[0].reason == "review" and
  .needs_review[0].base_commit == $base and .needs_review[0].wip_commit == $wip and
  .needs_review[0].next == ["git diff \($short)..kata/bq4e-f1f1f1f1f1f1", "\($answer) demo#bq4e \"<guidance>\""] and
  [.remaining[].qualified_id] == ["demo#a2j0","demo#zz11"] and [.remaining[].labels] == [[],["task"]] and
  [.remaining[].owner] == ["kata-pipeline-b20d9e898b16",null] and
  ([.completed[], .needs_decision[], .needs_review[], .remaining[]] |
    all(keys == ["base_commit","branch","issue_uid","labels","next","owner","pr_url","qualified_id","question","reason","run_id","wip_commit"]))
' "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'json report has the wrong shape'; }
printf 'ok - the JSON report carries every field for agents\n'

(cd "$repo" && "$report" older) >"$test_root/output" 2>&1 || fail 'report failed for a named run'
grep -Fx "Board older in $repo: stopped" "$test_root/output" >/dev/null || fail 'older: header is wrong'
grep -Fx 'Stop reason: three consecutive failed children' "$test_root/output" >/dev/null || fail 'older: stop reason is missing'
grep -Fx -e '- demo#bq4e: turn limit reached twice (run b1b1b1b1b1b1)' "$test_root/output" >/dev/null || fail 'older: review row is wrong'
grep -Fx "  branch kata/bq4e-b1b1b1b1b1b1, base $short_base, wip none" "$test_root/output" >/dev/null || fail 'older: branch line is wrong'
grep -Fx 'Remaining open (3)' "$test_root/output" >/dev/null || fail 'older: remaining count is wrong'
printf 'ok - a named stopped run reports its stop reason under the header\n'

ledger nullreason '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":false,"runs":[
  {"run_id":"a1a1a1a1a1a1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-a1a1a1a1a1a1","reason":null,"label":"needs-review"}]}'
handoff a1a1a1a1a1a1 '{"run_id":"a1a1a1a1a1a1","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":null,"label":"needs-review","branch":"kata/bq4e-a1a1a1a1a1a1","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":null}'
(cd "$repo" && "$report" nullreason) >"$test_root/output" 2>&1 || fail 'report failed for a handoff without a reason'
grep -Fx 'Needs review (1)' "$test_root/output" >/dev/null || fail 'null reason: the review group is missing'
grep -Fx -e '- demo#bq4e: handed off (run a1a1a1a1a1a1)' "$test_root/output" >/dev/null || fail 'null reason: the kata row is wrong'
printf 'ok - a handoff record without a reason still reports its kata\n'

# A board that swept more than once carries several entries for one kata; the latest one is its state.
ledger resweep '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"b1b1b1b1b1b1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-b1b1b1b1b1b1","reason":"turn_limit","label":"needs-review"},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"},
  {"run_id":"f1f1f1f1f1f1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-f1f1f1f1f1f1","reason":"review","label":"needs-review"},
  {"run_id":"c1c1c1c1c1c1","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-c1c1c1c1c1c1","commit":"'"$head"'","github":{"remote":"origin","repository":"o/r","base_branch":"main"},"pr_url":"https://github.com/o/r/pull/12"},
  {"run_id":"e2e2e2e2e2e2","kind":"empty"},
  {"run_id":"a2a2a2a2a2a2","kind":"completed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-a2a2a2a2a2a2","commit":"'"$wip"'","github":null,"pr_url":""},
  {"run_id":"e3e3e3e3e3e3","kind":"empty"}]}'
selected a2a2a2a2a2a2 '{"issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e"}'
cat >"$test_root/expected" <<EXPECTED
Board resweep in $repo: finished
Completed (2)
- demo#5fav on kata/5fav-c1c1c1c1c1c1
  https://github.com/o/r/pull/12
- demo#bq4e on kata/bq4e-a2a2a2a2a2a2
  no pull request
Needs decision (0)
Needs review (0)
Remaining open (3)
- demo#n4vr owned by kata-pipeline-d1d1d1d1d1d1, labels needs-decision
- demo#a2j0 owned by kata-pipeline-b20d9e898b16
- demo#zz11 owned by nobody, labels task
EXPECTED
(cd "$repo" && "$report" resweep) >"$test_root/output" 2>&1 || fail 'report failed for a ledger with several sweeps'
diff -u "$test_root/expected" "$test_root/output" || fail 'resweep: text report differs from the expected output'
ledger twice '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"b1b1b1b1b1b1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-b1b1b1b1b1b1","reason":"turn_limit","label":"needs-review"},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"},
  {"run_id":"f1f1f1f1f1f1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-f1f1f1f1f1f1","reason":"review","label":"needs-review"},
  {"run_id":"e2e2e2e2e2e2","kind":"empty"}]}'
(cd "$repo" && "$report" --json twice) >"$test_root/report.json" 2>"$test_root/output" || fail 'json report failed for a kata handed off twice'
jq -e '.completed == [] and [.needs_review[] | .run_id] == ["f1f1f1f1f1f1"] and .needs_review[0].reason == "review"' \
  "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'twice: the latest handoff is not the only one reported'; }
printf 'ok - a kata handed off and later finished, or handed off twice, is reported once by its latest run\n'

# An inspection stop names the child; the review prints the command that resumes it.
ledger inspect '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":false,"stop_reason":"child a1b2c3d4e5f6 needs inspection","stop_child":"a1b2c3d4e5f6","runs":[]}'
(cd "$repo" && "$report" inspect) >"$test_root/output" 2>&1 || fail 'report failed for an inspection stop'
grep -Fx "Board inspect in $repo: stopped" "$test_root/output" >/dev/null || fail 'inspect: header is wrong'
grep -Fx 'Stop reason: child a1b2c3d4e5f6 needs inspection' "$test_root/output" >/dev/null || fail 'inspect: stop reason is missing'
grep -Fx "  tracker -r a1b2c3d4e5f6 '/p/complete.dip'" "$test_root/output" >/dev/null || fail 'inspect: the resume command is missing'
(cd "$repo" && "$report" --json inspect) >"$test_root/report.json" 2>"$test_root/output" || fail 'json report failed for an inspection stop'
jq -e '.stop_child == "a1b2c3d4e5f6" and .pipeline == "/p/complete.dip" and
  .stop_reason == "child a1b2c3d4e5f6 needs inspection" and .completed == [] and .needs_review == []' \
  "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'inspect: json lacks the stop fields'; }
ledger badchild '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":false,"stop_reason":"child ../x needs inspection","stop_child":"../x","runs":[]}'
status=0
(cd "$repo" && "$report" badchild) >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "badchild exited $status, expected 1"
grep -F 'invalid board ledger' "$test_root/output" >/dev/null || fail 'badchild: message is wrong'
printf 'ok - an inspection stop prints the resume command, and a malformed child id is refused\n'

# Records a worker's run can write must not reach a pasteable command unchecked.
ledger poison-branch '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"b2b2b2b2b2b2","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/x","reason":"review","label":"needs-review"}]}'
# The $(id) below is the payload under test, not an expansion.
# shellcheck disable=SC2016
handoff b2b2b2b2b2b2 '{"run_id":"b2b2b2b2b2b2","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"review","label":"needs-review","branch":"kata/x$(id)","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":null}'
ledger poison-dots '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"c2c2c2c2c2c2","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/x","reason":"review","label":"needs-review"}]}'
handoff c2c2c2c2c2c2 '{"run_id":"c2c2c2c2c2c2","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"review","label":"needs-review","branch":"kata/x..main","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":null}'
ledger poison-pr '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"d2d2d2d2d2d2","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-d2d2d2d2d2d2","commit":"'"$head"'","github":{"remote":"origin","repository":"o/r","base_branch":"main"},"pr_url":"https://evil.example/o/r/pull/12"}]}'
selected d2d2d2d2d2d2 '{"issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav"}'
ledger poison-id '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"f2f2f2f2f2f2","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-f2f2f2f2f2f2","commit":"'"$head"'","github":null,"pr_url":""}]}'
selected f2f2f2f2f2f2 '{"issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav; id"}'
refuse() {
  status=0
  (cd "$repo" && "$report" "$@") >"$test_root/output" 2>&1 || status=$?
  [ "$status" -eq 1 ] || fail "$*: exited $status, expected 1"
  grep -F 'unsafe' "$test_root/output" >/dev/null || fail "$*: the refusal message is missing"
  if grep -F 'git diff' "$test_root/output" >/dev/null; then fail "$*: a command was printed"; fi
}
for poison in poison-branch poison-dots poison-pr poison-id; do
  refuse "$poison"
  refuse --json "$poison"
done
printf 'ok - a record with an unsafe branch, id, or pull request URL is refused whole\n'

(cd "$repo" && "$report" -h) >"$test_root/output" 2>&1 || fail '-h failed'
grep -F 'Usage: board-report' "$test_root/output" >/dev/null || fail '-h lacks usage'
status=0
(cd "$test_root" && "$report") >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "outside a repository exited $status, expected 1"
grep -Fx 'run this from inside the target Git repository' "$test_root/output" >/dev/null || fail 'outside a repository: message is wrong'
(cd "$repo" && HOME="$pipeline_dir" "$report" newer) >"$test_root/output" 2>&1 || fail 'report failed with the pipeline under HOME'
grep -Fx '  ~/answer demo#n4vr "<your answer>"' "$test_root/output" >/dev/null || fail 'a pipeline under HOME is not printed as ~/'
printf 'ok - board-report accepts -h, refuses to run outside a repository, and shortens paths under HOME\n'

status=0
(cd "$repo" && "$report" missing) >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "missing run exited $status, expected 1"
grep -F 'no board ledger' "$test_root/output" >/dev/null || fail 'missing run: message is wrong'
rm "$runs/f1f1f1f1f1f1/handoff.json"
status=0
(cd "$repo" && "$report" newer) >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "missing handoff exited $status, expected 1"
grep -F 'failed child f1f1f1f1f1f1 has no handoff record' "$test_root/output" >/dev/null || fail 'missing handoff: message is wrong'
printf 'ok - a missing ledger or handoff record is an error, not a guess\n'
