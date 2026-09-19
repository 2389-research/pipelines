#!/bin/sh
# ABOUTME: Exercises the runtime guard against remote Git and GitHub CLI commands.
# ABOUTME: Uses text fixtures only; no fixture command is executed and no network is contacted.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
guard="$pipeline_dir/check-no-remotes"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || cat "$test_root/output" >&2
  exit 1
}

new_runtime() {
  runtime="$test_root/$1"
  mkdir -p "$runtime/kata/scripts"
  cat >"$runtime/kata/scripts/local.sh" <<'SH'
#!/bin/sh
# ABOUTME: Fixture runtime script containing only local Git operations.
# ABOUTME: Exists as scanner input and is never executed by this test.
git status --short
SH
  cat >"$runtime/kata/complete.dip" <<'DIP'
workflow LocalOnly
  tool Check
    command:
      git status --short
DIP
  : >"$runtime/kata/board-report"
  : >"$runtime/kata/answer"
}

run_guard() {
  sh "$guard" "$runtime" >"$test_root/output" 2>&1
}

reject() {
  if run_guard; then fail "guard accepted $1"; fi
  grep -F 'remote Git or gh command' "$test_root/output" >/dev/null || fail "guard hid match for $1"
}

new_runtime allowed
run_guard || fail 'guard rejected local-only runtime'
printf 'ok - local Git commands pass the remote-command guard\n'

for operation in remote fetch push pull clone ls-remote; do
  new_runtime "direct-$operation"
  printf 'git %s example\n' "$operation" >>"$runtime/kata/scripts/local.sh"
  reject "git $operation"
done
new_runtime gh
printf 'gh pr create\n' >>"$runtime/kata/scripts/local.sh"
reject 'gh command'
printf 'ok - direct remote Git and gh commands are rejected\n'

new_runtime global-option
printf 'git -c push.followTags=false push origin HEAD\n' >>"$runtime/kata/scripts/local.sh"
reject 'Git command after a global option'
printf 'ok - remote Git after global options is rejected\n'

new_runtime untracked
git init -q "$runtime"
git -C "$runtime" add kata/scripts/local.sh kata/complete.dip kata/board-report kata/answer
git -C "$runtime" -c user.name=Check -c user.email=check@example.invalid commit -qm 'test: seed runtime'
printf 'git fetch origin\n' >"$runtime/kata/scripts/added-later.sh"
reject 'untracked runtime script'
printf 'ok - untracked runtime scripts are scanned\n'

new_runtime continued
cat >>"$runtime/kata/scripts/local.sh" <<'SH'
git \
  push origin HEAD
SH
reject 'continued remote Git command'
printf 'ok - backslash-newline remote Git commands are rejected\n'

new_runtime split-token
cat >>"$runtime/kata/scripts/local.sh" <<'SH'
git pu\
sh origin HEAD
SH
reject 'remote Git operation split across continued lines'
printf 'ok - tokens split across continued lines are rejected\n'

new_runtime extensionless
printf 'git push origin HEAD\n' >"$runtime/kata/scripts/runtime-helper"
reject 'extensionless runtime helper'
printf 'ok - extensionless runtime helpers are scanned\n'

new_runtime unreadable
ln -s "$runtime/missing-target" "$runtime/kata/scripts/unreadable.sh"
if run_guard; then fail 'guard accepted a scanner read failure'; fi
grep -F 'could not scan' "$test_root/output" >/dev/null || fail 'guard hid scanner read failure'
printf 'ok - scanner read failures fail the guard\n'
