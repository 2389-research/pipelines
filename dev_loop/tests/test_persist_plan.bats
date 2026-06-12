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

@test "unset DIP_ARTIFACT_DIR emits 'DIP_ARTIFACT_DIR is unset' error (#73)" {
  # Issue #73: the guard must distinguish truly-unset from set-but-stale so
  # the operator can tell setup_run-skipped from cleanup-race apart without
  # opening ${RUN_DIR}/env. This test pins the unset arm.
  # Executor decoupling (#61) still holds: the breadcrumb names only
  # DIP_ARTIFACT_DIR (the actionable knob), never the on-disk layout.
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
  # Pin the full actionable phrase: a regression that drops the trailing
  # "was setup_run executed?" suffix would still match a bare
  # "DIP_ARTIFACT_DIR is unset" substring and pass green.
  grep -q "DIP_ARTIFACT_DIR is unset; was setup_run executed?" \
    "${RUN_DIR}/persist_plan_error.txt"
  # The unset arm MUST NOT print the stale-path message (no path to print).
  ! grep -q "is not a directory" "${RUN_DIR}/persist_plan_error.txt"
  ! grep -q "tracker/runs" "${RUN_DIR}/persist_plan_error.txt"
  ! grep -q "no tracker run dir" "${RUN_DIR}/persist_plan_error.txt"
}

@test "stale DIP_ARTIFACT_DIR surfaces the value in the breadcrumb (#73)" {
  # Issue #73: when DIP_ARTIFACT_DIR is set but points at a non-existent dir
  # (cleanup race, operator tampering, mv/rm under us), the breadcrumb must
  # surface the stale value so the operator can diagnose without opening
  # ${RUN_DIR}/env. The unset arm would not name a path.
  stale="${WORKDIR}/.tracker/runs/trk-was-here-yesterday"
  cat > "${RUN_DIR}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
ALLOW_NO_CI='false'
DEV_LOOP_RUN_ID='${rid}'
DEV_LOOP_RUN_DIR='${RUN_DIR}'
DIP_ARTIFACT_DIR='${stale}'
EOF
  chmod 600 "${RUN_DIR}/env"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  # Pin the full actionable phrase including the surfaced path. -F treats the
  # interpolated path as a fixed string so regex metacharacters in WORKDIR (e.g.
  # `.`) can't loosen the match.
  grep -qF "DIP_ARTIFACT_DIR=${stale} is not a directory; was the artifact dir cleaned up under us?" \
    "${RUN_DIR}/persist_plan_error.txt"
  # The stale arm MUST NOT print the unset message.
  ! grep -qF "DIP_ARTIFACT_DIR is unset" "${RUN_DIR}/persist_plan_error.txt"
}
