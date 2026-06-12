#!/usr/bin/env bats
# test_persist_plan.bats — covers persist_plan.sh + sidecar branch/PR files.

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  mkdir -p "${DIP_ARTIFACT_DIR}/PlanMinimalPRs"

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/persist_plan.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  cp "${FIXTURES}/plan_sample.json" "${DIP_ARTIFACT_DIR}/PlanMinimalPRs/response.md"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "persists plan.json + extracts branch_name / pr_title / pr_body" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-plan" ]
  [ -f "${RUN_DIR}/plan.json" ]
  [ -f "${RUN_DIR}/branch_name.txt" ]
  [ -f "${RUN_DIR}/pr_title.txt" ]
  [ -f "${RUN_DIR}/pr_body.txt" ]
  branch="$(cat "${RUN_DIR}/branch_name.txt")"
  [ "${branch}" = "fix/42-writable-paths-anchor" ]
}

@test "plan with null/missing branch_name emits persist-failed (no 'null' sidecar)" {
  # Stage a plan response that has every required Plan field EXCEPT a real
  # branch_name (null). Without validation, jq -r would write the literal
  # string "null" into branch_name.txt and create_worktree would try to
  # `git worktree add -b null`. Issue #48: validation now emits persist-failed
  # so the .dip routes through CleanupWorktree + RatchetLog.
  cat > "${DIP_ARTIFACT_DIR}/PlanMinimalPRs/response.md" <<'JSON'
{
  "issue_number": 42,
  "branch_name": null,
  "pr_title": "fix: thing",
  "pr_body": "Body of the PR with enough content to pass the length check.",
  "changes": [{"path": "x", "action": "modify", "summary": "did a thing"}],
  "risk_class": "low",
  "test_strategy": "ran the gates and the bats suite locally"
}
JSON
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  grep -q "branch_name is missing" "${RUN_DIR}/persist_plan_error.txt"
  [ ! -f "${RUN_DIR}/branch_name.txt" ]
}

@test "missing response.md emits persist-failed" {
  rm -f "${DIP_ARTIFACT_DIR}/PlanMinimalPRs/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  grep -q "response missing" "${RUN_DIR}/persist_plan_error.txt"
}

@test "malformed response.md emits persist-failed" {
  printf 'not json at all\n' > "${DIP_ARTIFACT_DIR}/PlanMinimalPRs/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  [ -s "${RUN_DIR}/persist_plan_error.txt" ]
  [ ! -f "${RUN_DIR}/branch_name.txt" ]
}

@test "missing DIP_ARTIFACT_DIR emits neutral 'DIP_ARTIFACT_DIR is unset' error (#61)" {
  # Executor decoupling (#61): persist scripts must NOT name the executor's
  # on-disk layout (`.tracker/runs`) in their error breadcrumb. The actionable
  # signal is the env var name `DIP_ARTIFACT_DIR`, not the discovered root.
  cat > "${RUN_DIR}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
ALLOW_NO_CI='false'
DEV_LOOP_RUN_ID='${rid}'
DEV_LOOP_RUN_DIR='${RUN_DIR}'
EOF
  chmod 600 "${RUN_DIR}/env"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  # Pin the full actionable phrase (well-actually #3): a regression that drops
  # the trailing "was setup_run executed?" suffix would still match a bare
  # "DIP_ARTIFACT_DIR is unset" substring and pass green.
  grep -q "DIP_ARTIFACT_DIR is unset or not a directory; was setup_run executed?" \
    "${RUN_DIR}/persist_plan_error.txt"
  ! grep -q "tracker/runs" "${RUN_DIR}/persist_plan_error.txt"
  ! grep -q "no tracker run dir" "${RUN_DIR}/persist_plan_error.txt"
}
