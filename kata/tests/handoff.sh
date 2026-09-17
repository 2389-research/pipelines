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
real_git=$(command -v git)

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
  extra_path=${2:-}
  if (cd "$repo" && PATH="${extra_path:+$extra_path:}$PATH" TRACKER_RUN_DIR="$run_dir" TRACKER_RUN_ID=test TRACKER_WORKDIR="$repo" sh "$script") \
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

new_repo git-status-failure
printf 'half done\n' >"$repo/partial.txt"
badgit="$test_root/badgit"
mkdir -p "$badgit"
cat >"$badgit/git" <<GIT
#!/bin/sh
# ABOUTME: Wraps the real git but fails "git status" to simulate a broken repository.
# ABOUTME: Delegates every other subcommand so the rest of a handoff still runs normally.
set -eu
if [ "\$1" = status ]; then
  printf 'fatal: fixture git status failure\n' >&2
  exit 128
fi
exec "$real_git" "\$@"
GIT
chmod +x "$badgit/git"
handoff git-status-failure "$badgit"
[ ! -e "$run_dir/handoff.json" ] || fail 'git-status-failure: handoff.json was written after a broken git status'
if grep -Fx 'handoff-ok' "$test_root/output" >/dev/null; then
  fail 'git-status-failure: handoff-ok was printed despite a broken git status'
fi
printf 'ok - a broken git status stops the handoff instead of treating a broken tree as clean\n'
