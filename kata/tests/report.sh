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
  {"run_id":"b1b1b1b1b1b1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-b1b1b1b1b1b1","reason":"turn_limit","label":"needs-review"}]}'
touch -t 202001010000 "$runs/older/board/state.json"
ledger newer '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"c1c1c1c1c1c1","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-c1c1c1c1c1c1","commit":"'"$head"'","github":{"remote":"origin","repository":"o/r","base_branch":"main"},"pr_url":"https://github.com/o/r/pull/12"},
  {"run_id":"d1d1d1d1d1d1","kind":"failed","issue_uid":"01DECISION0000000000000000","branch":"kata/n4vr-d1d1d1d1d1d1","reason":"decision","label":"needs-decision"},
  {"run_id":"f1f1f1f1f1f1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-f1f1f1f1f1f1","reason":"review","label":"needs-review"},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"}]}'
mkdir -p "$runs/c1c1c1c1c1c1"
printf '%s\n' '{"issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav"}' >"$runs/c1c1c1c1c1c1/selected.json"
handoff d1d1d1d1d1d1 '{"run_id":"d1d1d1d1d1d1","issue_uid":"01DECISION0000000000000000","qualified_id":"demo#n4vr","reason":"decision","label":"needs-decision","branch":"kata/n4vr-d1d1d1d1d1d1","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":"Should the CLI accept --format=json\nas well as --json?"}'
handoff f1f1f1f1f1f1 '{"run_id":"f1f1f1f1f1f1","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"review","label":"needs-review","branch":"kata/bq4e-f1f1f1f1f1f1","base_commit":"'"$base"'","wip_commit":"'"$wip"'","start_branch":"main","question":null}'
handoff b1b1b1b1b1b1 '{"run_id":"b1b1b1b1b1b1","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"turn_limit","label":"needs-review","branch":"kata/bq4e-b1b1b1b1b1b1","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":null}'

cat >"$test_root/expected" <<EXPECTED
Board newer in $repo: finished
Completed (1)
  demo#5fav  kata/5fav-c1c1c1c1c1c1  https://github.com/o/r/pull/12
Needs decision (1)
  demo#n4vr  Q: Should the CLI accept --format=json as well as --json?
      $pipeline_dir/answer demo#n4vr "<your answer>"
Needs review (1)
  demo#bq4e  review rejected; branch kata/bq4e-f1f1f1f1f1f1 (base 1234abcd, wip 5678ef01); run f1f1f1f1f1f1
      git diff $base..kata/bq4e-f1f1f1f1f1f1
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
  .needs_review[0].next == ["git diff \($base)..kata/bq4e-f1f1f1f1f1f1", "\($answer) demo#bq4e \"<guidance>\""] and
  [.remaining[].qualified_id] == ["demo#a2j0","demo#zz11"] and [.remaining[].labels] == [[],["task"]] and
  [.remaining[].owner] == ["kata-pipeline-b20d9e898b16",null] and
  ([.completed[], .needs_decision[], .needs_review[], .remaining[]] |
    all(keys == ["base_commit","branch","issue_uid","labels","next","owner","pr_url","qualified_id","question","reason","run_id","wip_commit"]))
' "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'json report has the wrong shape'; }
printf 'ok - the JSON report carries every field for agents\n'

(cd "$repo" && "$report" older) >"$test_root/output" 2>&1 || fail 'report failed for a named run'
grep -Fx "Board older in $repo: stopped" "$test_root/output" >/dev/null || fail 'older: header is wrong'
grep -Fx 'Stop reason: three consecutive failed children' "$test_root/output" >/dev/null || fail 'older: stop reason is missing'
grep -Fx '  demo#bq4e  turn limit reached twice; branch kata/bq4e-b1b1b1b1b1b1 (base 1234abcd, wip none); run b1b1b1b1b1b1' \
  "$test_root/output" >/dev/null || fail 'older: review row is wrong'
grep -Fx 'Remaining open (3)' "$test_root/output" >/dev/null || fail 'older: remaining count is wrong'
printf 'ok - a named stopped run reports its stop reason\n'

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
