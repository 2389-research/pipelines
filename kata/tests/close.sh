#!/bin/sh
# ABOUTME: Exercises close refusals, the trunk fast-forward, and landing retries.
# ABOUTME: Uses a fixture kata and disposable Git repositories; never touches a real daemon.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
script="$pipeline_dir/scripts/close-selected.sh"
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
# ABOUTME: Answers show from fixture files and records or fails the close call.
# ABOUTME: Keeps close tests isolated from every real kata workspace and daemon.
set -eu
verb=$1
shift
[ "$1" = --workspace ] || { printf 'fixture kata: expected --workspace, got %s\n' "$1" >&2; exit 91; }
fixture="$2/.tracker/close-fixture"
shift 2
printf '%s %s\n' "$verb" "$*" >>"$fixture/kata.log"
case "$verb" in
  show)
    status=open
    owner=kata-pipeline-test
    [ ! -f "$fixture/status" ] || status=$(cat "$fixture/status")
    [ ! -f "$fixture/owner" ] || owner=$(cat "$fixture/owner")
    jq -n --arg uid "$1" --arg status "$status" --arg owner "$owner" \
      '{issue:{uid:$uid,status:$status,owner:$owner}}'
    ;;
  close)
    if [ -e "$fixture/fail-close" ]; then
      rm -f "$fixture/fail-close"
      printf 'fixture kata: close failed once\n' >&2
      exit 7
    fi
    printf '%s\n' "$*" >"$fixture/close.args"
    ;;
  *) printf 'fixture kata: unexpected call %s %s\n' "$verb" "$*" >&2; exit 2 ;;
esac
SH
chmod +x "$test_root/bin/kata"
export PATH="$test_root/bin:$PATH"
real_git=$(command -v git)
export real_git
mkdir -p "$test_root/git-bin"
cat >"$test_root/git-bin/git" <<'SH'
#!/bin/sh
# ABOUTME: Injects read failures while all other operations use the real isolated Git repository.
# ABOUTME: Selects failures from fixture files without contacting a daemon or remote.
set -eu
fixture=.tracker/close-fixture
if [ "$*" = 'worktree list --porcelain' ] && [ -e "$fixture/fail-worktrees" ]; then
  printf 'fixture git: worktree listing failed\n' >&2
  exit 7
fi
if [ "$1" = status ] && [ -e "$fixture/fail-status" ]; then
  count=0
  [ ! -e "$fixture/status-count" ] || count=$(cat "$fixture/status-count")
  count=$((count + 1))
  printf '%s\n' "$count" >"$fixture/status-count"
  if [ "$count" = "$(cat "$fixture/fail-status")" ]; then
    printf 'dirty\n' >>file
    printf 'fixture git: status failed\n' >&2
    exit 7
  fi
fi
exec "$real_git" "$@"
SH
chmod +x "$test_root/git-bin/git"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || cat "$test_root/output" >&2
  exit 1
}

run_close() {
  (cd "$repo" && PATH="$test_root/git-bin:$PATH" TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$repo" sh "$script") \
    >"$test_root/output" 2>&1
}

reject() {
  if run_close; then fail "close accepted: $1"; fi
  grep -F "$1" "$test_root/output" >/dev/null || fail "wrong refusal, wanted: $1"
}

assert_untouched() {
  [ "$(git -C "$repo" rev-parse refs/heads/main)" = "$base" ] || fail "$1: main changed"
  [ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = kata/5fav-test ] || fail "$1: checkout changed"
  git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test || fail "$1: task branch was deleted"
  [ ! -e "$fixture/close.args" ] || fail "$1: kata close ran"
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
  git -C "$repo" commit -qm 'test: seed closure repository'
  base=$(git -C "$repo" rev-parse HEAD)
  git -C "$repo" switch -qc kata/5fav-test
  run_dir="$repo/.tracker/runs/test"
  fixture="$repo/.tracker/close-fixture"
  mkdir -p "$run_dir" "$fixture" "$repo/.tracker/turn_overrides"
  printf '450\n' >"$repo/.tracker/turn_overrides/Implement"
  jq -n --arg workspace "$repo" --arg base "$base" \
    '{workspace:$workspace,issue_uid:"01ARZ3NDEKTSV4RRFFQ69G5FAV",qualified_id:"demo#5fav",
      branch:"kata/5fav-test",base_commit:$base,actor:"kata-pipeline-test",trunk:"main"}' \
    >"$run_dir/selected.json"
}

add_evidence() {
  printf 'change\n' >"$repo/file"
  git -C "$repo" add file
  git -C "$repo" commit -qm 'test: task change'
  head=$(git -C "$repo" rev-parse HEAD)
  printf 'test command\n' >"$run_dir/verification.txt"
  printf 'Implemented the selected behavior and verified its acceptance checks.\n' >"$run_dir/completion.md"
  printf '%s\n' "$head" >"$run_dir/review-correctness.approved"
  printf '%s\n' "$head" >"$run_dir/review-scope.approved"
}

new_repo refusals
reject 'no task commit'
printf 'change\n' >"$repo/file"
reject 'working tree is not clean'
git -C "$repo" add file
git -C "$repo" commit -qm 'test: task change'
head=$(git -C "$repo" rev-parse HEAD)
reject 'verification evidence is missing'
printf 'test command\n' >"$run_dir/verification.txt"
reject 'completion summary is missing'
printf 'short\n' >"$run_dir/completion.md"
printf '%s\n' "$head" >"$run_dir/review-correctness.approved"
printf '%s\n' "$head" >"$run_dir/review-scope.approved"
reject 'completion summary is too short'
printf 'Implemented the selected behavior and verified its acceptance checks.\n' >"$run_dir/completion.md"
printf '%s\n' "$base" >"$run_dir/review-correctness.approved"
reject 'does not approve current commit'
printf '%s\n' "$head" >"$run_dir/review-correctness.approved"
printf '%s\n' "$base" >"$run_dir/review-scope.approved"
reject 'does not approve current commit'
printf '%s\n' "$head" >"$run_dir/review-scope.approved"
git -C "$repo" switch -qc kata/other
reject 'task branch changed'
git -C "$repo" switch -q kata/5fav-test
cp "$run_dir/selected.json" "$test_root/saved-state"
jq --arg workspace "$test_root" '.workspace = $workspace' "$run_dir/selected.json" >"$test_root/wrong-state"
cp "$test_root/wrong-state" "$run_dir/selected.json"
reject 'tracker workspace changed'
cp "$test_root/saved-state" "$run_dir/selected.json"
printf 'closed\n' >"$fixture/status"
reject 'selected kata is no longer open and owned by this run'
assert_untouched closed
rm "$fixture/status"
printf 'somebody-else\n' >"$fixture/owner"
reject 'selected kata is no longer open and owned by this run'
assert_untouched owner
printf 'ok - close rejects incomplete evidence, stale state, and lost ownership\n'

new_repo divergent
add_evidence
divergent_tree=$(git -C "$repo" rev-parse 'HEAD^{tree}')
divergent_head=$(printf 'test: divergent task change\n' | git -C "$repo" commit-tree "$divergent_tree")
git -C "$repo" update-ref refs/heads/kata/5fav-test "$divergent_head"
git -C "$repo" reset -q --hard "$divergent_head"
head=$(git -C "$repo" rev-parse HEAD)
printf '%s\n' "$head" >"$run_dir/review-correctness.approved"
printf '%s\n' "$head" >"$run_dir/review-scope.approved"
reject 'task history no longer descends from the claimed base'
assert_untouched divergent
printf 'ok - divergent task history is refused before any change\n'

new_repo land
add_evidence
run_close || fail 'land: close-selected exited non-zero'
[ "$(git -C "$repo" rev-parse refs/heads/main)" = "$head" ] || fail 'land: main was not fast-forwarded'
[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = main ] || fail 'land: checkout did not return to trunk'
if git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test; then fail 'land: task branch survived'; fi
grep -F -- "--commit $head" "$fixture/close.args" >/dev/null || fail 'land: close call lacks commit'
grep -F 'Landed on main' "$fixture/close.args" >/dev/null || fail 'land: completion lacks landing'
grep -Fx "Landed demo#5fav on main at $head" "$test_root/output" >/dev/null || fail 'land: stdout lacks landing'
grep -Fx 'close-ok' "$test_root/output" >/dev/null || fail 'land: close-ok was not printed'
[ ! -e "$repo/.tracker/turn_overrides/Implement" ] || fail 'land: turn override survived'
printf 'ok - an approved task lands, closes, switches to trunk, and deletes its branch\n'

new_repo moved
add_evidence
git -C "$repo" switch -q main
printf 'later\n' >"$repo/later.txt"
git -C "$repo" add later.txt
git -C "$repo" commit -qm 'test: trunk moved after the claim'
moved_tip=$(git -C "$repo" rev-parse main)
git -C "$repo" switch -q kata/5fav-test
reject 'trunk main moved from'
[ "$(git -C "$repo" rev-parse main)" = "$moved_tip" ] || fail 'moved: main changed'
[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = kata/5fav-test ] || fail 'moved: checkout changed'
git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test || fail 'moved: branch deleted'
[ ! -e "$fixture/close.args" ] || fail 'moved: kata close ran'
printf 'ok - a trunk that moved after claim is refused before any change\n'

new_repo failonce
add_evidence
: >"$fixture/fail-close"
reject 'fixture kata: close failed once'
[ "$(git -C "$repo" rev-parse main)" = "$head" ] || fail 'failonce: main was not landed'
[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = kata/5fav-test ] || fail 'failonce: checkout changed'
git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test || fail 'failonce: branch deleted'
run_close || fail 'failonce: rerun failed'
[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = main ] || fail 'failonce: rerun did not switch'
if git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test; then fail 'failonce: rerun left branch'; fi
grep -Fx 'close-ok' "$test_root/output" >/dev/null || fail 'failonce: no close-ok'
printf 'ok - a failed close leaves landed trunk and a rerun finishes safely\n'

new_repo worktree
add_evidence
git -C "$repo" worktree add "$test_root/wt-main" main >/dev/null 2>&1
reject 'trunk main is checked out in another worktree'
assert_untouched worktree
printf 'ok - a trunk checked out in another worktree is refused\n'

new_repo missingtrunk
add_evidence
jq '.trunk = "release"' "$run_dir/selected.json" >"$run_dir/state.tmp"
mv "$run_dir/state.tmp" "$run_dir/selected.json"
reject 'trunk release is missing'
assert_untouched missingtrunk
printf 'ok - a missing trunk branch is refused\n'

new_repo predates
add_evidence
jq 'del(.trunk)' "$run_dir/selected.json" >"$run_dir/state.tmp"
mv "$run_dir/state.tmp" "$run_dir/selected.json"
reject 'predates landing on close'
assert_untouched predates
printf 'ok - a run without recorded trunk is refused for inspection\n'

new_repo worktreefailure
add_evidence
git -C "$repo" worktree add "$test_root/wt-failure" main >/dev/null 2>&1
: >"$fixture/fail-worktrees"
reject 'could not list worktrees'
assert_untouched worktreefailure
if grep -Fx 'close-ok' "$test_root/output"; then fail 'worktreefailure: success marker emitted'; fi
printf 'ok - a failed worktree listing refuses landing before any change\n'

new_repo firststatusfailure
add_evidence
printf '1\n' >"$fixture/fail-status"
reject 'could not inspect working tree'
assert_untouched firststatusfailure
git -C "$repo" diff --quiet && fail 'firststatusfailure: dirty fixture missing'
[ -e "$repo/.tracker/turn_overrides/Implement" ] || fail 'firststatusfailure: override removed'
if grep -Fx 'close-ok' "$test_root/output"; then fail 'firststatusfailure: success marker emitted'; fi
printf 'ok - an initial status failure refuses landing and closing\n'

new_repo secondstatusfailure
add_evidence
printf '2\n' >"$fixture/fail-status"
reject 'could not inspect working tree during landing'
[ "$(git -C "$repo" rev-parse main)" = "$head" ] || fail 'secondstatusfailure: approved landing lost'
[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = kata/5fav-test ] || fail 'secondstatusfailure: checkout changed'
git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test || fail 'secondstatusfailure: branch deleted'
[ ! -e "$fixture/close.args" ] || fail 'secondstatusfailure: kata close ran'
git -C "$repo" diff --quiet && fail 'secondstatusfailure: dirty fixture missing'
[ -e "$repo/.tracker/turn_overrides/Implement" ] || fail 'secondstatusfailure: override removed'
if grep -Fx 'close-ok' "$test_root/output"; then fail 'secondstatusfailure: success marker emitted'; fi
printf 'ok - a pre-close status failure keeps the landing but refuses close and cleanup\n'
