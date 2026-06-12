#!/usr/bin/env bats
# test_persist_selected_issue.bats — covers persist_selected_issue.sh +
# sidecar selected_issue_number.txt.

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  mkdir -p "${DIP_ARTIFACT_DIR}/SelectNextIssue"

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/persist_selected_issue.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  cp "${FIXTURES}/selected_issue_sample.json" "${DIP_ARTIFACT_DIR}/SelectNextIssue/response.md"
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

@test "missing response.md emits persist-failed (status 0) with error file" {
  # Issue #48: post-bootstrap failures emit ctx.tool_marker=persist-failed
  # so the .dip routes through CleanupWorktree + RatchetLog.
  rm -f "${DIP_ARTIFACT_DIR}/SelectNextIssue/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  grep -q "response missing" "${RUN_DIR}/persist_selected_error.txt"
}

@test "malformed response.md emits persist-failed" {
  # jq parse failure on the response is a post-bootstrap failure.
  printf 'not valid json {{{\n' > "${DIP_ARTIFACT_DIR}/SelectNextIssue/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  [ -s "${RUN_DIR}/persist_selected_error.txt" ]
}

@test "non-numeric issue_number emits persist-failed" {
  # The validator in persist_selected_issue rejects non-positive-integer
  # issue_number so create_worktree + push_and_open_pr never interpolate the
  # literal string "null" into branch names. Convert from exit 1 to
  # persist-failed (issue #48).
  cat > "${DIP_ARTIFACT_DIR}/SelectNextIssue/response.md" <<'JSON'
{
  "issue_number": "not-a-number",
  "title": "x",
  "url": "https://example.test/x",
  "author": "anon",
  "created_at": "2026-01-01T00:00:00Z",
  "selection_rationale": "long enough rationale string"
}
JSON
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  grep -q "issue_number" "${RUN_DIR}/persist_selected_error.txt"
  [ ! -f "${RUN_DIR}/selected_issue_number.txt" ]
}
