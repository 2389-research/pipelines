#!/usr/bin/env bats
# ABOUTME: Bats tests for the Track B smoke assertion helpers in lib.sh.
# ABOUTME: Builds synthetic fixture run dirs so the helpers can be exercised
# ABOUTME: without invoking tracker. The full-pipeline smoke run is opt-in
# ABOUTME: (see smoke.sh + README.md) and lives outside this bats file.

setup() {
  LIB="${BATS_TEST_DIRNAME}/lib.sh"
  TMPDIR="$(mktemp -d -t track_b_smoke.XXXXXX)"
  export TMPDIR
  # Source the helpers under test.
  # shellcheck disable=SC1090
  . "${LIB}"
}

teardown() {
  rm -rf "${TMPDIR}"
}

# Build a synthetic .tracker/runs/<rid>/ tree for assertions.
# Usage: make_run <workdir> <rid> <node_id> [response_body] [activity_lines...]
make_run() {
  workdir=$1
  rid=$2
  node=$3
  body=${4:-}
  run_dir="${workdir}/.tracker/runs/${rid}"
  mkdir -p "${run_dir}/${node}"
  if [ -n "${body}" ]; then
    printf '%s\n' "${body}" > "${run_dir}/${node}/response.md"
  fi
  shift 4 || true
  # Remaining args become activity.jsonl lines.
  : > "${run_dir}/activity.jsonl"
  for line in "$@"; do
    printf '%s\n' "${line}" >> "${run_dir}/activity.jsonl"
  done
}

@test "track_b_run_dir errors when no .tracker/runs exists" {
  run track_b_run_dir "${TMPDIR}"
  [ "$status" -ne 0 ]
}

@test "track_b_run_dir picks the most recent run" {
  mkdir -p "${TMPDIR}/.tracker/runs/aaa11111"
  mkdir -p "${TMPDIR}/.tracker/runs/bbb22222"
  # Force the second one newer.
  touch -t 202601010000 "${TMPDIR}/.tracker/runs/aaa11111"
  touch -t 202612010000 "${TMPDIR}/.tracker/runs/bbb22222"
  run track_b_run_dir "${TMPDIR}"
  [ "$status" -eq 0 ]
  case "${output}" in
    */bbb22222) ;;
    *) printf 'unexpected: %s\n' "${output}" >&2; return 1 ;;
  esac
}

@test "track_b_assert_response_exists fails when response.md missing" {
  make_run "${TMPDIR}" run1 Exit ''
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_response_exists "${run_dir}" Exit
  [ "$status" -ne 0 ]
}

@test "track_b_assert_response_exists fails when response.md empty" {
  make_run "${TMPDIR}" run1 Exit
  : > "${TMPDIR}/.tracker/runs/run1/Exit/response.md"
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_response_exists "${run_dir}" Exit
  [ "$status" -ne 0 ]
}

@test "track_b_assert_response_exists passes when response.md non-empty" {
  make_run "${TMPDIR}" run1 Exit 'Pipeline complete.'
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_response_exists "${run_dir}" Exit
  [ "$status" -eq 0 ]
}

@test "track_b_assert_no_tool_calls_in_response passes on plain text" {
  make_run "${TMPDIR}" run1 Exit 'Acknowledged. Pipeline ready.'
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_no_tool_calls_in_response "${run_dir}" Exit
  [ "$status" -eq 0 ]
}

@test "track_b_assert_no_tool_calls_in_response fails when TOOL CALL present" {
  body='TURN 1
TOOL CALL: bash
INPUT:
{"command": "ls"}
TOOL RESULT: bash'
  make_run "${TMPDIR}" run1 Exit "${body}"
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_no_tool_calls_in_response "${run_dir}" Exit
  [ "$status" -ne 0 ]
  case "${output}" in
    *FAIL*) ;;
    *) printf 'expected FAIL marker, got: %s\n' "${output}" >&2; return 1 ;;
  esac
}

@test "track_b_assert_no_tool_calls_in_response: prose-mention of tool call OK" {
  # The agent prose may describe what it "would" have done — only literal
  # `TOOL CALL:` at line-start (tracker's transcript marker) is the regression
  # signal.
  body='I would normally make a TOOL CALL but tool_access is none, so acknowledging only.'
  make_run "${TMPDIR}" run1 Exit "${body}"
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_no_tool_calls_in_response "${run_dir}" Exit
  [ "$status" -eq 0 ]
}

@test "track_b_assert_no_tool_events_in_activity passes on quiet activity" {
  line1='{"ts":"x","source":"pipeline","type":"stage_started","node_id":"Exit"}'
  line2='{"ts":"x","source":"agent","type":"llm_text","node_id":"Exit"}'
  make_run "${TMPDIR}" run1 Exit 'ok' "${line1}" "${line2}"
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_no_tool_events_in_activity "${run_dir}" Exit
  [ "$status" -eq 0 ]
}

@test "track_b_assert_no_tool_events_in_activity fails on tool_call_start" {
  line='{"ts":"x","source":"agent","type":"tool_call_start","node_id":"Exit","tool_name":"bash"}'
  make_run "${TMPDIR}" run1 Exit 'irrelevant' "${line}"
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_no_tool_events_in_activity "${run_dir}" Exit
  [ "$status" -ne 0 ]
}

@test "track_b_assert_no_tool_events_in_activity: other node's tool calls ignored" {
  # Some upstream tool node may legitimately have tool_call_start events. We
  # only care about the converted agent.
  line='{"ts":"x","source":"agent","type":"tool_call_start","node_id":"SomeOtherNode","tool_name":"bash"}'
  make_run "${TMPDIR}" run1 Exit 'ok' "${line}"
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_no_tool_events_in_activity "${run_dir}" Exit
  [ "$status" -eq 0 ]
}

@test "track_b_assert_node_reached fails when stage_started absent" {
  line='{"ts":"x","source":"pipeline","type":"pipeline_started"}'
  make_run "${TMPDIR}" run1 Exit 'ok' "${line}"
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_node_reached "${run_dir}" Exit
  [ "$status" -ne 0 ]
}

@test "track_b_assert_node_reached passes when stage_started present" {
  line='{"ts":"x","source":"pipeline","type":"stage_started","node_id":"Exit"}'
  make_run "${TMPDIR}" run1 Exit 'ok' "${line}"
  run_dir=$(track_b_run_dir "${TMPDIR}")
  run track_b_assert_node_reached "${run_dir}" Exit
  [ "$status" -eq 0 ]
}
