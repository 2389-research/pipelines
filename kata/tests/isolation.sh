#!/bin/sh
# ABOUTME: Proves the isolation snippet keeps a test away from the operator's Git hooks, Git config, home, and Tracker state.
# ABOUTME: Plants a hostile global Git configuration in a fixture home, then shows a commit and a Tracker run under the snippet never touch it.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
command -v tracker >/dev/null
command -v jq >/dev/null
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || tail -n 40 "$test_root/output" >&2
  exit 1
}
# A sourcing failure exits a bash 3.2 sh with status 0 when an EXIT trap runs, so the file is checked by name first.
[ -f "$pipeline_dir/tests/isolate.sh" ] || fail 'kata/tests/isolate.sh is missing'

# A fixture stands in for the operator's home: a global Git configuration whose hook refuses every commit,
# whose default branch is trunk, and whose identity is not the test's.
operator_home="$test_root/operator"
mkdir -p "$operator_home/hooks" "$operator_home/xdg/tracker"
OPERATOR_HOOK_LOG="$test_root/hook.log"
export OPERATOR_HOOK_LOG
cat >"$operator_home/hooks/pre-commit" <<'SH'
#!/bin/sh
printf 'fired\n' >>"$OPERATOR_HOOK_LOG"
exit 1
SH
chmod +x "$operator_home/hooks/pre-commit"
cat >"$operator_home/.gitconfig" <<GITCONFIG
[core]
hooksPath = $operator_home/hooks
[init]
defaultBranch = trunk
[user]
name = Operator
email = operator@example.invalid
[commit]
gpgsign = false
GITCONFIG
# No provider key here: if the snippet ever stopped exporting XDG_CONFIG_HOME, Tracker would read this
# file and refuse with "no providers configured", so the tool-only run below failing proves the fixture key, not this decoy, was read.
printf 'KATA_ISOLATION_DECOY=operator-config-must-stay-unread\n' >"$operator_home/xdg/tracker/.env"

# Control: with that home in force, a fresh repository is born on trunk and the hook refuses the commit.
status=0
(
  HOME="$operator_home" XDG_CONFIG_HOME="$operator_home/xdg"
  export HOME XDG_CONFIG_HOME
  unset GIT_CONFIG_GLOBAL
  git init -q "$test_root/control"
  printf 'x\n' >"$test_root/control/file.txt"
  git -C "$test_root/control" add file.txt
  git -C "$test_root/control" commit -q -m 'control commit'
) >"$test_root/output" 2>&1 || status=$?
[ "$status" -ne 0 ] || fail 'control: the operator hook did not refuse the commit'
[ -f "$OPERATOR_HOOK_LOG" ] || fail 'control: the operator hook did not fire'
[ "$(git -C "$test_root/control" symbolic-ref --short HEAD)" = trunk ] || fail 'control: the operator default branch was not used'
rm "$OPERATOR_HOOK_LOG"

# Under the snippet, the same home is in the environment, yet nothing of it reaches Git or Tracker.
HOME="$operator_home"
XDG_CONFIG_HOME="$operator_home/xdg"
export HOME XDG_CONFIG_HOME
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
[ "$HOME" = "$KATA_ISOLATE_ROOT/home" ] || fail "HOME is $HOME, expected $KATA_ISOLATE_ROOT/home"
[ "$XDG_CONFIG_HOME" = "$KATA_ISOLATE_ROOT/config" ] || fail "XDG_CONFIG_HOME is $XDG_CONFIG_HOME, expected $KATA_ISOLATE_ROOT/config"
[ "$XDG_STATE_HOME" = "$KATA_ISOLATE_ROOT/state" ] || fail "XDG_STATE_HOME is $XDG_STATE_HOME, expected $KATA_ISOLATE_ROOT/state"
[ "$GIT_CONFIG_NOSYSTEM" = 1 ] && [ "$TRACKER_NO_UPDATE_CHECK" = 1 ] || fail 'GIT_CONFIG_NOSYSTEM or TRACKER_NO_UPDATE_CHECK is not 1'
[ "$(cat "$XDG_CONFIG_HOME/tracker/.env")" = 'OPENAI_API_KEY=fixture-not-a-key' ] || fail 'the fixture Tracker .env is wrong'
git init -q "$test_root/isolated"
printf 'x\n' >"$test_root/isolated/file.txt"
git -C "$test_root/isolated" add file.txt
git -C "$test_root/isolated" commit -q -m 'isolated commit' >"$test_root/output" 2>&1 || fail 'isolated: the commit failed under the snippet'
[ ! -e "$OPERATOR_HOOK_LOG" ] || fail 'isolated: the operator hook fired under the snippet'
[ "$(git -C "$test_root/isolated" symbolic-ref --short HEAD)" = main ] || fail 'isolated: the fixture default branch was not used'
[ "$(git -C "$test_root/isolated" log -1 --format=%an)" = 'Kata test' ] || fail 'isolated: the commit author is not the fixture identity'
[ "$(git -C "$test_root/isolated" config --show-origin --get init.defaultBranch)" = "$(printf 'file:%s\tmain' "$GIT_CONFIG_GLOBAL")" ] ||
  fail 'isolated: init.defaultBranch does not come from the fixture global config'
printf 'ok - the isolation snippet keeps Git away from the operator hooks, config, and identity\n'

# A real tool-only Tracker run finds the fixture provider key and keeps its state under the fixture directories.
cat >"$test_root/touch.dip" <<'DIP'
workflow IsolationProbe
  goal: "Prove Tracker runs on the fixture key and writes state under the fixture directories."
  start: Touch
  exit: Exit

  tool Touch
    label: "Touch"
    timeout: 1m
    marker_grep: "^touched$"
    command: printf 'touched\n'

  tool Exit
    label: "Done"
    timeout: 5s
    command: true

  edges
    Touch -> Exit  on touched
DIP
tracker --git off --workdir "$test_root/isolated" --json --no-tui "$test_root/touch.dip" >"$test_root/output" 2>&1 </dev/null ||
  fail 'the tool-only Tracker run failed under the snippet'
run_id=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "pipeline_started")][0].run_id' <"$test_root/output")
case "$run_id" in ''|null) fail 'the Tracker log has no pipeline_started event' ;; esac
[ -f "$XDG_STATE_HOME/tracker/runs/$run_id/checkpoint.json" ] || fail "Tracker kept no state under $XDG_STATE_HOME/tracker/runs/$run_id"
[ ! -e "$operator_home/.local" ] || fail 'Tracker wrote under the operator home'
[ ! -e "$KATA_ISOLATE_ROOT/home/.local" ] || fail 'Tracker wrote under the fixture home instead of XDG_STATE_HOME'
printf 'ok - a Tracker run under the snippet keeps its state under the fixture directories\n'
