#!/bin/sh
# ABOUTME: Checks kata/answer: refuses bad targets, comments and unassigns a pipeline-owned kata, reports the result.
# ABOUTME: Uses a fixture kata on PATH; never touches a real daemon.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
answer="$pipeline_dir/answer"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
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
    case "$1" in demo#5fav|01ARZ3NDEKTSV4RRFFQ69G5FAV) ;; *) exit 92 ;; esac
    [ ! -e "$fixture/show-fails-after-release" ] || [ -n "$owner" ] || { printf 'daemon unreachable\n' >&2; exit 1; }
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
    [ ! -e "$fixture/list-fails" ] || { printf 'daemon unreachable\n' >&2; exit 1; }
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
  rm -f "$fixture/kata.log" "$fixture/comment" "$fixture/show-fails-after-release" "$fixture/list-fails"
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
grep -Fx 'Released demo#5fav' "$test_root/output" >/dev/null || fail 'released line is missing'
printf 'ok - answer comments the reply, releases the pipeline claim, and reports the release, owner, and labels\n'

reset_fixture open kata-pipeline-abc
: >"$fixture/show-fails-after-release"
run_answer demo#5fav 'Ship it'
[ "$status" -ne 0 ] || fail 'answer exited 0 although the post-release show failed'
grep -F 'daemon unreachable' "$test_root/output" >/dev/null || fail 'post-release show failure is not reported'
if grep -F 'Owner:' "$test_root/output" >/dev/null; then fail 'owner line was printed after a failed show'; fi
grep -F 'unassign' "$fixture/kata.log" >/dev/null || fail 'claim was not released before the failed show'
grep -Fx 'Released demo#5fav' "$test_root/output" >/dev/null || fail 'released line is missing after a failed show'
reset_fixture open kata-pipeline-abc
: >"$fixture/list-fails"
run_answer demo#5fav 'Ship it'
[ "$status" -ne 0 ] || fail 'answer exited 0 although the post-release list failed'
grep -F 'daemon unreachable' "$test_root/output" >/dev/null || fail 'post-release list failure is not reported'
if grep -F 'Labels:' "$test_root/output" >/dev/null; then fail 'labels line was printed after a failed list'; fi
printf 'ok - answer fails loudly when the post-release show or list fails\n'

reset_fixture open kata-pipeline-abc
run_answer demo#nope 'Ship it'
[ "$status" -eq 1 ] || fail "unknown reference exited $status, expected 1"
grep -Fx 'kata show demo#nope failed with status 92; check the reference and the workspace binding' "$test_root/output" >/dev/null ||
  fail 'unknown reference: message is missing'
if grep -F 'unassign' "$fixture/kata.log" >/dev/null; then fail 'unknown reference: unassign was called'; fi
status=0
(cd "$test_root" && "$answer" demo#5fav 'Ship it') >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "outside a repository exited $status, expected 1"
grep -Fx 'run this from inside the target Git repository' "$test_root/output" >/dev/null || fail 'outside a repository: message is wrong'
printf 'ok - answer names an unknown reference and refuses to run outside a repository\n'

for flag in -h --help; do
  run_answer "$flag"
  [ "$status" -eq 0 ] || fail "$flag exited $status"
  grep -F 'Usage: answer' "$test_root/output" >/dev/null || fail "$flag lacks usage"
  grep -F 'next board sweep' "$test_root/output" >/dev/null || fail "$flag usage does not say next board sweep"
  if grep -F 'next board run' "$test_root/output" >/dev/null; then fail "$flag usage still says next board run"; fi
done
run_answer demo#5fav
[ "$status" -eq 2 ] || fail "missing text exited $status, expected 2"
grep -F 'Usage: answer' "$test_root/output" >/dev/null || fail 'missing text lacks usage'
printf 'ok - answer prints usage for -h, --help, and wrong arguments\n'
