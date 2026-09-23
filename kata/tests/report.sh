#!/bin/sh
# ABOUTME: Checks kata/board-report against fixture ledgers and a fixture open-issue list.
# ABOUTME: Compares the text report exactly, checks the JSON shape, and proves unsafe ledger entries are refused.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
report="$pipeline_dir/board-report"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
command -v jq >/dev/null
# The report prints commands as ~/... under the operator's home; the snippet's fixture home keeps the expected text fixed.
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"

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

# The board writes one self-contained ledger per run; these helpers stand one in for a test.
ledger() {
  mkdir -p "$runs/$1/board"
  printf '%s\n' "$2" >"$runs/$1/board/state.json"
}

ledger_jq() {
  # Builds a ledger whose entry needs a literal control character; jq's own serializer escapes it
  # correctly, so the byte never passes through the shell as text.
  mkdir -p "$runs/$1/board"
  out="$runs/$1/board/state.json"
  shift
  jq -n "$@" >"$out"
}

ledger older '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":false,"stop_reason":"three consecutive failed children","runs":[
  {"run_id":"b1b1b1b1b1b1","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/bq4e-b1b1b1b1b1b1","reason":"turn_limit","label":"needs-review","base_commit":"'"$base"'","wip_commit":null,"trunk":"main","question":null}]}'
touch -t 202001010000 "$runs/older/board/state.json"
ledger newer '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":true,"runs":[
  {"run_id":"c1c1c1c1c1c1","kind":"completed","issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav","branch":"kata/5fav-c1c1c1c1c1c1","base_commit":"'"$base"'","commit":"'"$head"'"},
  {"run_id":"d1d1d1d1d1d1","kind":"failed","issue_uid":"01DECISION0000000000000000","qualified_id":"demo#n4vr","branch":"kata/n4vr-d1d1d1d1d1d1","reason":"decision","label":"needs-decision","base_commit":"'"$base"'","wip_commit":null,"trunk":"main","question":"Should the CLI accept --format=json\nas well as --json?"},
  {"run_id":"f1f1f1f1f1f1","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/bq4e-f1f1f1f1f1f1","reason":"review","label":"needs-review","base_commit":"'"$base"'","wip_commit":"'"$wip"'","trunk":"main","question":null},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"}]}'

# Tracker reflows the review at 76 columns: every line is short, no line depends on its indent,
# and every command is whole on one line with its path quoted.
cat >"$test_root/expected" <<EXPECTED
Board newer in $repo: finished
Completed (1)
- demo#5fav: landed 9abcdef09abc (run c1c1c1c1c1c1)
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
jq -e --arg repo "$repo" --arg answer "$pipeline_dir/answer" --arg base "$base" --arg wip "$wip" --arg head "$head" --arg short "$short_base" '
  .board_run_id == "newer" and .workspace == $repo and .pipeline == "/p/board-item.dip" and .finished == true and
  .stop_reason == null and (has("stop_child") | not) and
  [.completed[].qualified_id] == ["demo#5fav"] and .completed[0].run_id == "c1c1c1c1c1c1" and
  .completed[0].commit == $head and .completed[0].next == [] and
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
    all(keys == ["base_commit","branch","commit","issue_uid","labels","next","owner","qualified_id","question","reason","run_id","wip_commit"]))
' "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'json report has the wrong shape'; }
printf 'ok - the JSON report carries every field for agents\n'

(cd "$repo" && "$report" older) >"$test_root/output" 2>&1 || fail 'report failed for a named run'
grep -Fx "Board older in $repo: stopped" "$test_root/output" >/dev/null || fail 'older: header is wrong'
grep -Fx 'Stop reason: three consecutive failed children' "$test_root/output" >/dev/null || fail 'older: stop reason is missing'
grep -Fx -e '- demo#bq4e: turn limit reached twice (run b1b1b1b1b1b1)' "$test_root/output" >/dev/null || fail 'older: review row is wrong'
grep -Fx "  branch kata/bq4e-b1b1b1b1b1b1, base $short_base, wip none" "$test_root/output" >/dev/null || fail 'older: branch line is wrong'
grep -Fx 'Remaining open (3)' "$test_root/output" >/dev/null || fail 'older: remaining count is wrong'
(cd "$repo" && "$report" --json older) >"$test_root/report.json" 2>"$test_root/output" || fail 'json report failed for the older run'
jq -e '.stop_reason == "three consecutive failed children" and .pipeline == "/p/board-item.dip" and (has("stop_child") | not)' \
  "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'older: json stop fields are wrong'; }
printf 'ok - a named stopped run reports its stop reason and carries no resume child\n'

ledger nullreason '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":false,"runs":[
  {"run_id":"a1a1a1a1a1a1","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/bq4e-a1a1a1a1a1a1","reason":null,"label":"needs-review","base_commit":"'"$base"'","wip_commit":null,"trunk":"main","question":null}]}'
(cd "$repo" && "$report" nullreason) >"$test_root/output" 2>&1 || fail 'report failed for a handoff without a reason'
grep -Fx 'Needs review (1)' "$test_root/output" >/dev/null || fail 'null reason: the review group is missing'
grep -Fx -e '- demo#bq4e: handed off (run a1a1a1a1a1a1)' "$test_root/output" >/dev/null || fail 'null reason: the kata row is wrong'
printf 'ok - a handoff record without a reason still reports its kata\n'

# A production run id is the parent id and a random suffix joined by a hyphen; the report must accept it
# and print it whole in the text and the JSON.
ledger hyphenated '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":true,"runs":[
  {"run_id":"abcdef012345-9a9a9a","kind":"completed","issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav","branch":"kata/5fav-abcdef012345-9a9a9a","base_commit":"'"$base"'","commit":"'"$head"'"}]}'
(cd "$repo" && "$report" hyphenated) >"$test_root/output" 2>&1 || fail 'report failed for a hyphenated run id'
grep -Fx -e '- demo#5fav: landed 9abcdef09abc (run abcdef012345-9a9a9a)' "$test_root/output" >/dev/null || fail 'hyphenated: the completed row is wrong'
(cd "$repo" && "$report" --json hyphenated) >"$test_root/report.json" 2>"$test_root/output" || fail 'json report failed for a hyphenated run id'
jq -e '.completed[0].run_id == "abcdef012345-9a9a9a"' "$test_root/report.json" >/dev/null || fail 'hyphenated: json run id is wrong'
printf 'ok - a hyphenated parent-and-suffix run id is accepted and printed whole\n'

# A board that swept more than once carries several entries for one kata; the latest one is its state.
ledger resweep '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":true,"runs":[
  {"run_id":"b1b1b1b1b1b1","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/bq4e-b1b1b1b1b1b1","reason":"turn_limit","label":"needs-review","base_commit":"'"$base"'","wip_commit":null,"trunk":"main","question":null},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"},
  {"run_id":"f1f1f1f1f1f1","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/bq4e-f1f1f1f1f1f1","reason":"review","label":"needs-review","base_commit":"'"$base"'","wip_commit":null,"trunk":"main","question":null},
  {"run_id":"c1c1c1c1c1c1","kind":"completed","issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav","branch":"kata/5fav-c1c1c1c1c1c1","base_commit":"'"$base"'","commit":"'"$head"'"},
  {"run_id":"e2e2e2e2e2e2","kind":"empty"},
  {"run_id":"a2a2a2a2a2a2","kind":"completed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/bq4e-a2a2a2a2a2a2","base_commit":"'"$base"'","commit":"'"$wip"'"},
  {"run_id":"e3e3e3e3e3e3","kind":"empty"}]}'
cat >"$test_root/expected" <<EXPECTED
Board resweep in $repo: finished
Completed (2)
- demo#5fav: landed 9abcdef09abc (run c1c1c1c1c1c1)
- demo#bq4e: landed 5678ef015678 (run a2a2a2a2a2a2)
Needs decision (0)
Needs review (0)
Remaining open (3)
- demo#n4vr owned by kata-pipeline-d1d1d1d1d1d1, labels needs-decision
- demo#a2j0 owned by kata-pipeline-b20d9e898b16
- demo#zz11 owned by nobody, labels task
EXPECTED
(cd "$repo" && "$report" resweep) >"$test_root/output" 2>&1 || fail 'report failed for a ledger with several sweeps'
diff -u "$test_root/expected" "$test_root/output" || fail 'resweep: text report differs from the expected output'
ledger twice '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":true,"runs":[
  {"run_id":"b1b1b1b1b1b1","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/bq4e-b1b1b1b1b1b1","reason":"turn_limit","label":"needs-review","base_commit":"'"$base"'","wip_commit":null,"trunk":"main","question":null},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"},
  {"run_id":"f1f1f1f1f1f1","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/bq4e-f1f1f1f1f1f1","reason":"review","label":"needs-review","base_commit":"'"$base"'","wip_commit":null,"trunk":"main","question":null},
  {"run_id":"e2e2e2e2e2e2","kind":"empty"}]}'
(cd "$repo" && "$report" --json twice) >"$test_root/report.json" 2>"$test_root/output" || fail 'json report failed for a kata handed off twice'
jq -e '.completed == [] and [.needs_review[] | .run_id] == ["f1f1f1f1f1f1"] and .needs_review[0].reason == "review"' \
  "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'twice: the latest handoff is not the only one reported'; }
printf 'ok - a kata handed off and later finished, or handed off twice, is reported once by its latest run\n'

# The ledger validation guards every run id, because each names a branch and an actor; an unsafe one is
# refused whole before any record is printed.
ledger badrunid '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":true,"runs":[
  {"run_id":"x; rm -rf ~","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/bq4e","reason":"review","label":"needs-review","base_commit":"'"$base"'","wip_commit":null,"trunk":"main","question":null}]}'
status=0
(cd "$repo" && "$report" badrunid) >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "badrunid exited $status, expected 1"
grep -F 'invalid board ledger' "$test_root/output" >/dev/null || fail 'badrunid: message is wrong'
if grep -F 'demo#' "$test_root/output" >/dev/null; then fail 'badrunid: a record was printed before the refusal'; fi
printf 'ok - a ledger run id that is not branch-safe is refused whole\n'

# Ledger fields a worker's records fed into the ledger must not reach a pasteable command unchecked. The
# $(id) below must stay a literal string in the branch field, so the single quotes are the point here.
# shellcheck disable=SC2016
ledger poison-branch '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":true,"runs":[
  {"run_id":"b2b2b2b2b2b2","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/x$(id)","reason":"review","label":"needs-review","base_commit":"'"$base"'","wip_commit":null,"trunk":"main","question":null}]}'
ledger poison-dots '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":true,"runs":[
  {"run_id":"c2c2c2c2c2c2","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/x..main","reason":"review","label":"needs-review","base_commit":"'"$base"'","wip_commit":null,"trunk":"main","question":null}]}'
ledger poison-landed '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":true,"runs":[
  {"run_id":"d2d2d2d2d2d2","kind":"completed","issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav","branch":"kata/5fav-d2d2d2d2d2d2","base_commit":"'"$base"'","commit":"deadbeef; rm -rf /"}]}'
ledger poison-id '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":true,"runs":[
  {"run_id":"f2f2f2f2f2f2","kind":"completed","issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav; id","branch":"kata/5fav-f2f2f2f2f2f2","base_commit":"'"$base"'","commit":"'"$head"'"}]}'
ledger poison-commit '{"workspace":"'"$repo"'","pipeline":"/p/board-item.dip","finished":true,"runs":[
  {"run_id":"a4a4a4a4a4a4","kind":"failed","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","branch":"kata/bq4e-a4a4a4a4a4a4","reason":"review","label":"needs-review","base_commit":"deadbeef; rm -rf /","wip_commit":null,"trunk":"main","question":null}]}'
# shellcheck disable=SC2016 # $base is a jq variable from --arg; ledger_jq is not literally named jq.
ledger_jq poison-ctrl --arg repo "$repo" --arg base "$base" '{workspace:$repo,pipeline:"/p/board-item.dip",finished:true,runs:[
  {run_id:"a5a5a5a5a5a5",kind:"failed",issue_uid:"01REVIEW000000000000000000",qualified_id:"demo#bq4e",
   branch:("kata/x" + ([27] | implode) + "y"),reason:"review",label:"needs-review",base_commit:$base,wip_commit:null,trunk:"main",question:null}]}'
refuse() {
  status=0
  (cd "$repo" && "$report" "$@") >"$test_root/output" 2>&1 || status=$?
  [ "$status" -eq 1 ] || fail "$*: exited $status, expected 1"
  grep -F 'unsafe' "$test_root/output" >/dev/null || fail "$*: the refusal message is missing"
  if grep -F 'demo#' "$test_root/output" >/dev/null; then fail "$*: a record was printed before the refusal"; fi
}
for invalid in missing null; do
  mkdir -p "$runs/commit-$invalid/board"
  jq --arg invalid "$invalid" '.runs = [.runs[0]] | if $invalid == "missing" then del(.runs[0].commit) else .runs[0].commit = null end' \
    "$runs/newer/board/state.json" >"$runs/commit-$invalid/board/state.json"
  refuse "commit-$invalid"
  refuse --json "commit-$invalid"
done
printf 'ok - completed items without a non-null landed commit are refused\n'

for poison in poison-branch poison-dots poison-landed poison-id poison-commit poison-ctrl; do
  refuse "$poison"
  refuse --json "$poison"
done
printf 'ok - a ledger entry with an unsafe branch, commit, or id is refused whole\n'

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
printf 'ok - a missing ledger is an error, not a guess\n'
