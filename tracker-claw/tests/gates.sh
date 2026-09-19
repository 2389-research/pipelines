#!/bin/sh
# ABOUTME: Drives real Tracker console gates through stop, invalid input, EOF, and resume.
# ABOUTME: Uses a provider-free fixture so offline checks never impersonate an agent.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
fixture="$pipeline_dir/tests/fixtures/gates.dip"
test_root=$(mktemp -d)
cleanup() {
  cleanup_status=$1
  if [ "$cleanup_status" -eq 0 ]; then
    rm -rf "$test_root"
  else
    printf 'gate test logs retained at %s\n' "$test_root" >&2
  fi
}
trap 'cleanup $?' EXIT
trap 'exit 130' HUP INT TERM
XDG_CONFIG_HOME="$test_root/config"
XDG_STATE_HOME="$test_root/state"
export XDG_CONFIG_HOME XDG_STATE_HOME

# Tracker constructs a native LLM client before running even a zero-agent graph.
# Give that unused client an unreachable endpoint without loading configured credentials.
unset ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY OPENAI_COMPAT_API_KEY
unset ANTHROPIC_BASE_URL OPENAI_BASE_URL GEMINI_BASE_URL OPENAI_COMPAT_BASE_URL
OPENAI_API_KEY=unused-offline-gate-fixture
OPENAI_BASE_URL=http://127.0.0.1:1
export OPENAI_API_KEY OPENAI_BASE_URL

dippin simulate "$fixture" --all-paths >"$test_root/events" 2>"$test_root/paths"
if ! jq -se '
  [.[] | select(.event == "node_enter" and .kind == "agent")] | length == 0
' "$test_root/events" >/dev/null; then
  printf 'provider-free gate fixture unexpectedly contains an agent node\n' >&2
  exit 1
fi

run_tracker() {
  workdir=$1
  input=$2
  log=$3
  mkdir -p "$workdir"
  if [ "$input" = EOF ]; then
    tracker --no-tui --git off -w "$workdir" "$fixture" </dev/null >"$log" 2>&1
  else
    printf '%s\n' "$input" | tracker --no-tui --git off -w "$workdir" "$fixture" >"$log" 2>&1
  fi
}

run_tracker "$test_root/stop" 'probe request
Stop' "$test_root/stop.log"
grep -E 'node=Exit[[:space:]]+executing node "Exit"' "$test_root/stop.log" >/dev/null

mkdir -p "$test_root/default"
printf 'probe request\n' | tracker --no-tui --git off -w "$test_root/default" "$fixture" \
  >"$test_root/default.log" 2>&1
grep -E 'node=Exit[[:space:]]+executing node "Exit"' "$test_root/default.log" >/dev/null
if grep -E 'node=Continue[[:space:]]+executing node "Continue"' "$test_root/default.log" >/dev/null; then
  printf 'auto-approval did not choose the safe Stop default\n' >&2
  exit 1
fi

for failure in invalid missing; do
  workdir="$test_root/$failure"
  log="$test_root/$failure.log"
  input='probe request
bogus'
  [ "$failure" = missing ] && input=EOF
  if run_tracker "$workdir" "$input" "$log"; then
    printf '%s input unexpectedly passed the gate\n' "$failure" >&2
    exit 1
  fi

  run_id=$(find "$workdir/.tracker/runs" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sed -n '1p')
  [ -n "$run_id" ] || {
    printf '%s input did not save a resumable run\n' "$failure" >&2
    exit 1
  }
  resume_input=Stop
  [ "$failure" = missing ] && resume_input='probe request
Stop'
  printf '%s\n' "$resume_input" | tracker --no-tui --git off -w "$workdir" -r "$run_id" "$fixture" \
    >"$test_root/$failure-resume.log" 2>&1
  grep -E 'node=Exit[[:space:]]+executing node "Exit"' "$test_root/$failure-resume.log" >/dev/null
done

printf 'ok - real Tracker gates default to stop, reject bad input and EOF, and resume\n'
