#!/bin/sh
# ABOUTME: Verifies drainrev.sh hands tracker the repository root, the pipeline, and extra flags.
# ABOUTME: Puts a recording stand-in for tracker first on PATH, so no model provider is called.
set -eu

roborev_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
drainrev="$roborev_dir/drainrev.sh"
pipeline="$roborev_dir/roborev_issue_fixer.dip"
test_root=$(mktemp -d)
test_root=$(CDPATH='' cd -- "$test_root" && pwd -P)
cleanup() {
  cleanup_status=$1
  if [ "$cleanup_status" -eq 0 ]; then
    rm -rf "$test_root"
  else
    printf 'drainrev test logs retained at %s\n' "$test_root" >&2
  fi
}
trap 'cleanup $?' EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'drainrev: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_root/bin" "$test_root/repo/sub/dir" "$test_root/plain"
cat >"$test_root/bin/tracker" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$DRAINREV_TEST_ARGS"
EOF
chmod +x "$test_root/bin/tracker"
DRAINREV_TEST_ARGS="$test_root/args"
PATH="$test_root/bin:$PATH"
# Keep git from finding a repository above the scratch tree, so "outside git" holds anywhere.
GIT_CEILING_DIRECTORIES=$test_root
export DRAINREV_TEST_ARGS PATH GIT_CEILING_DIRECTORIES
repo="$test_root/repo"
git -c init.defaultBranch=main -C "$repo" init -q

# expect_args NAME ARG...: the last tracker call received exactly ARG..., one per line.
expect_args() {
  name=$1
  shift
  printf '%s\n' "$@" >"$test_root/want"
  if ! cmp -s "$test_root/want" "$DRAINREV_TEST_ARGS"; then
    diff "$test_root/want" "$DRAINREV_TEST_ARGS" >&2 || true
    fail "$name: tracker got the wrong arguments"
  fi
  rm -f "$DRAINREV_TEST_ARGS"
}

usage=$(sh "$drainrev" --help) || fail "--help exited nonzero"
case $usage in
  usage:*) ;;
  *) fail "--help printed no usage line" ;;
esac
[ ! -e "$DRAINREV_TEST_ARGS" ] || fail "--help ran tracker"

(cd "$repo/sub/dir" && sh "$drainrev") || fail "run from a subdirectory failed"
expect_args "no arguments" -w "$repo" "$pipeline" --param drain_queue=true

sh "$drainrev" "$repo/sub" --no-tui --param review_id=7 || fail "run with a repo argument failed"
expect_args "repo and flags" -w "$repo" "$pipeline" --param drain_queue=true --no-tui --param review_id=7

(cd "$repo" && sh "$drainrev" --no-tui) || fail "run with only flags failed"
expect_args "flags only" -w "$repo" "$pipeline" --param drain_queue=true --no-tui

ln -s "$drainrev" "$test_root/bin/drainrev"
(cd "$repo" && drainrev) || fail "run through a symlink failed"
expect_args "symlink" -w "$repo" "$pipeline" --param drain_queue=true

if (cd "$test_root/plain" && sh "$drainrev") 2>"$test_root/err"; then
  fail "a directory outside git succeeded"
fi
grep -q 'not a git repository' "$test_root/err" || fail "outside git: no git error shown"
[ ! -e "$DRAINREV_TEST_ARGS" ] || fail "outside git: tracker ran anyway"
