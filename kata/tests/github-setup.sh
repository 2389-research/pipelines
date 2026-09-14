#!/bin/sh
# ABOUTME: Exercises GitHub claim setup against real isolated Git repositories.
# ABOUTME: Stubs only authenticated GitHub queries and Kata ownership at CLI boundaries.
set -eu

KATA_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
export GIT_CONFIG_GLOBAL="$TMP_ROOT/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GH_SETUP_LOG="$TMP_ROOT/gh.log"
mkdir "$TMP_ROOT/bin"
ln -s "$KATA_DIR/tests/fake-kata.sh" "$TMP_ROOT/bin/kata"
cat >"$TMP_ROOT/bin/gh" <<'SH'
#!/bin/sh
# ABOUTME: Supplies authenticated repository metadata at the GitHub CLI boundary.
# ABOUTME: Logs calls so setup tests detect unwanted queries before selection.
set -eu
printf '%s\n' "$*" >>"$GH_SETUP_LOG"
[ "${GH_SETUP_FAIL:-false}" != true ] || { printf 'authentication failed\n' >&2; exit 1; }
[ "$*" = 'repo view github.com/acme/demo --json nameWithOwner,defaultBranchRef' ] || { printf 'unexpected gh call: %s\n' "$*" >&2; exit 1; }
printf '%s\n' '{"nameWithOwner":"Acme/Demo","defaultBranchRef":{"name":"release"}}'
SH
chmod +x "$TMP_ROOT/bin/gh"
export PATH="$TMP_ROOT/bin:$PATH"
mkdir "$TMP_ROOT/without-gh"
for executable in sh cat mkdir git jq kata grep dirname sed wc tr rm; do
  ln -s "$(command -v "$executable")" "$TMP_ROOT/without-gh/$executable"
done

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { printf '%s' "$1" | grep -F -- "$2" >/dev/null || fail "expected [$2] in [$1]"; }
git init -q -b release "$TMP_ROOT/seed"
git -C "$TMP_ROOT/seed" config user.name tester
git -C "$TMP_ROOT/seed" config user.email test@example.com
printf '.fake-kata-log\n' >"$TMP_ROOT/seed/.gitignore"
git -C "$TMP_ROOT/seed" add .gitignore
git -C "$TMP_ROOT/seed" commit -qm init
initial=$(git -C "$TMP_ROOT/seed" rev-parse HEAD)
printf 'remote default branch\n' >"$TMP_ROOT/seed/default.txt"
git -C "$TMP_ROOT/seed" add default.txt
git -C "$TMP_ROOT/seed" commit -qm default
base=$(git -C "$TMP_ROOT/seed" rev-parse HEAD)
git clone -q --bare "$TMP_ROOT/seed" "$TMP_ROOT/remote.git"
for url in https://github.com/acme/demo.git git@github.com:acme/demo.git ssh://git@github.com/acme/demo.git ssh://git@github.com:22/acme/demo.git; do
  git config --global --add "url.file://$TMP_ROOT/remote.git.insteadOf" "$url"
done

new_repo() {
  repo=$TMP_ROOT/$1
  git clone -q "$TMP_ROOT/remote.git" "$repo"
  repo=$(cd "$repo" && pwd -P)
  git -C "$repo" config user.name tester
  git -C "$repo" config user.email test@example.com
  git -C "$repo" switch -qc feat/previous "$initial"
  printf 'previous feature\n' >"$repo/previous.txt"
  git -C "$repo" add previous.txt
  git -C "$repo" commit -qm previous
  previous=$(git -C "$repo" rev-parse HEAD)
  git -C "$repo" remote remove origin
  : >"$GH_SETUP_LOG"
}
run_setup() {
  mkdir -p "$repo/.tracker/runs/test"
  (cd "$repo" && TRACKER_RUN_DIR="$repo/.tracker/runs/test" TRACKER_WORKDIR="$repo" TRACKER_RUN_ID=test sh -c "$(cat "$KATA_DIR/scripts/claim-next.sh")") 2>&1
}
assert_unclaimed() {
  [ "$(git -C "$repo" branch --show-current)" = feat/previous ] || fail 'failed setup changed branch'
  [ "$(git -C "$repo" rev-parse HEAD)" = "$previous" ] || fail 'failed setup changed HEAD'
  [ ! -e "$repo/.tracker/runs/test/selected.json" ] || fail 'failed setup saved selection'
  if [ -e "$repo/.fake-kata-log" ] && grep '^claim ' "$repo/.fake-kata-log" >/dev/null; then fail 'failed setup claimed issue'; fi
}

for transport in https scp ssh ssh-port; do
  new_repo "$transport"
  case "$transport" in
    https) url=https://github.com/acme/demo.git ;;
    scp) url=git@github.com:acme/demo.git ;;
    ssh) url=ssh://git@github.com/acme/demo.git ;;
    ssh-port) url=ssh://git@github.com:22/acme/demo.git ;;
  esac
  git -C "$repo" remote add origin "$url"
  output=$(run_setup) || fail "$output"
  contains "$output" claim-ok
  [ "$(git -C "$repo" branch --show-current)" = kata/5fav-test ] || fail 'fresh task branch missing'
  [ "$(git -C "$repo" rev-parse HEAD)" = "$base" ] || fail 'task branch did not use fetched default branch'
  [ "$(git -C "$repo" rev-parse feat/previous)" = "$previous" ] || fail 'previous branch changed'
  [ ! -e "$repo/previous.txt" ] || fail 'previous feature leaked into task branch'
  jq -e --arg base "$base" '.base_commit == $base and .github == {remote:"origin",repository:"Acme/Demo",base_branch:"release"}' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'GitHub publication metadata missing'
done
printf 'ok - GitHub URL transports start fresh branches at the fetched custom default\n'

for scenario in ambiguity authentication missing-gh fetch push-mismatch multiple-push multiple-fetch collision; do
  new_repo "$scenario"
  git -C "$repo" remote add upstream https://github.com/acme/demo.git
  case "$scenario" in
    ambiguity) git -C "$repo" remote add backup git@github.com:acme/demo.git; expected='multiple GitHub remotes' ;;
    authentication) expected='authentication failed' ;;
    missing-gh) expected='gh is required' ;;
    fetch) git config --global --unset-all "url.file://$TMP_ROOT/remote.git.insteadOf" '^https://'; git config --global "url.file://$TMP_ROOT/missing.git.insteadOf" https://github.com/acme/demo.git; expected='fetch' ;;
    push-mismatch) git -C "$repo" remote set-url --push upstream https://github.com/other/repo.git; expected='push' ;;
    multiple-push) git -C "$repo" remote set-url --add --push upstream https://github.com/acme/demo.git; git -C "$repo" remote set-url --add --push upstream git@github.com:acme/demo.git; expected='push' ;;
    multiple-fetch) git -C "$repo" remote set-url --add upstream git@github.com:acme/demo.git; expected='fetch' ;;
    collision) git -C "$repo" branch kata/5fav-test; expected='already exists' ;;
  esac
  if [ "$scenario" = authentication ]; then
    if output=$(GH_SETUP_FAIL=true run_setup); then fail "$scenario succeeded"; fi
  elif [ "$scenario" = missing-gh ]; then
    if output=$(PATH="$TMP_ROOT/without-gh" run_setup); then fail "$scenario succeeded"; fi
  else
    if output=$(run_setup); then fail "$scenario succeeded"; fi
  fi
  contains "$output" "$expected"
  assert_unclaimed
  if [ "$scenario" = fetch ]; then
    git config --global --unset-all "url.file://$TMP_ROOT/missing.git.insteadOf"
    git config --global --add "url.file://$TMP_ROOT/remote.git.insteadOf" https://github.com/acme/demo.git
  fi
done
printf 'ok - ambiguous, unauthenticated, unsafe, and unavailable remotes stop before claim\n'

for scenario in origin-preferred only-github no-github empty conflict; do
  new_repo "$scenario"
  case "$scenario" in
    origin-preferred) git -C "$repo" remote add origin https://github.com/acme/demo.git; git -C "$repo" remote add other https://github.com/other/repo.git; selected_remote=origin ;;
    only-github) git -C "$repo" remote add origin "$TMP_ROOT/remote.git"; git -C "$repo" remote add upstream https://github.com/acme/demo.git; selected_remote=upstream ;;
    no-github) git -C "$repo" remote add origin "$TMP_ROOT/remote.git" ;;
    empty|conflict) git -C "$repo" remote add origin https://github.com/acme/demo.git ;;
  esac
  case "$scenario" in
    empty) output=$(FAKE_KATA_MODE=empty run_setup) || fail "$output"; contains "$output" queue-empty; assert_unclaimed; [ ! -s "$GH_SETUP_LOG" ] || fail 'empty queue queried GitHub'; [ ! -e "$repo/.git/FETCH_HEAD" ] || fail 'empty queue fetched' ;;
    conflict) if output=$(FAKE_KATA_MODE=conflict run_setup); then fail 'claim race succeeded'; fi; contains "$output" 'claim failed'; [ "$(git -C "$repo" branch --show-current)" = feat/previous ] || fail 'claim race changed branch'; [ ! -e "$repo/.tracker/runs/test/selected.json" ] || fail 'claim race saved selection'; git -C "$repo" show-ref --verify --quiet refs/heads/kata/5fav-test && fail 'claim race created branch' ;;
    no-github) output=$(GH_SETUP_FAIL=true run_setup) || fail "$output"; [ ! -s "$GH_SETUP_LOG" ] || fail 'non-GitHub repo queried GitHub'; jq -e --arg base "$previous" '.github == null and .base_commit == $base' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'non-GitHub base mismatch' ;;
    *) output=$(run_setup) || fail "$output"; jq -e --arg remote "$selected_remote" '.github.remote == $remote' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'wrong GitHub remote selected' ;;
  esac
done
printf 'ok - remote preference, non-GitHub setup, empty queues, and claim races are bounded\n'
