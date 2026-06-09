#!/usr/bin/env bats
# test_persist_selected_issue.bats — covers persist_selected_issue.sh +
# sidecar selected_issue_number.txt.

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  mkdir -p "${TRACKER_RUN_DIR}/SelectNextIssue"

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/persist_selected_issue.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  cp "${FIXTURES}/selected_issue_sample.json" "${TRACKER_RUN_DIR}/SelectNextIssue/response.md"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "persists selected_issue.json + emits issue number sidecar" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-selected" ]
  [ -f "${RUN_DIR}/selected_issue.json" ]
  [ -f "${RUN_DIR}/selected_issue_number.txt" ]
  num="$(cat "${RUN_DIR}/selected_issue_number.txt")"
  [ "${num}" = "42" ]
}

@test "missing response.md exits non-zero with error file" {
  rm -f "${TRACKER_RUN_DIR}/SelectNextIssue/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -ne 0 ]
  grep -q "response missing" "${RUN_DIR}/persist_selected_error.txt"
}
