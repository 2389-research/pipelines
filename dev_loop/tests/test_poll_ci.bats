#!/usr/bin/env bats
# test_poll_ci.bats — covers ci-success / ci-failed / ci-timeout / ci-no-checks.
# Real `gh pr checks --json` returns bucket / state / name / workflow; the
# bucket field is the resolved outcome enum (pass / fail / pending / skipping /
# cancel). Shims emit that shape, not the older conclusion-based fixture.

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  printf '7' > "${RUN_DIR}/pr_number.txt"

  SHIM="${TMPDIR}/bin"
  mkdir -p "${SHIM}"
  export PATH="${SHIM}:${PATH}"
  export DEV_LOOP_CI_POLL_INTERVAL=1
  export DEV_LOOP_CI_POLL_TIMEOUT=3
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/poll_ci.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

write_gh_shim() {
  cat > "${SHIM}/gh" <<EOF
#!/bin/sh
$1
EOF
  chmod +x "${SHIM}/gh"
}

@test "no checks emits ci-no-checks" {
  write_gh_shim 'printf "[]"'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-no-checks" ]
}

@test "all bucket=pass emits ci-success" {
  write_gh_shim 'printf "[{\"bucket\":\"pass\",\"state\":\"COMPLETED\",\"name\":\"smoke\",\"workflow\":\"ci\"}]"'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-success" ]
}

@test "pass + skipping still emits ci-success" {
  write_gh_shim 'printf "[{\"bucket\":\"pass\",\"state\":\"COMPLETED\",\"name\":\"a\",\"workflow\":\"w\"},{\"bucket\":\"skipping\",\"state\":\"COMPLETED\",\"name\":\"b\",\"workflow\":\"w\"}]"'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-success" ]
}

@test "one bucket=fail emits ci-failed" {
  write_gh_shim 'printf "[{\"bucket\":\"pass\",\"state\":\"COMPLETED\",\"name\":\"a\",\"workflow\":\"w\"},{\"bucket\":\"fail\",\"state\":\"COMPLETED\",\"name\":\"b\",\"workflow\":\"w\"}]"'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-failed" ]
}

@test "bucket=cancel emits ci-failed (fail-closed default)" {
  write_gh_shim 'printf "[{\"bucket\":\"cancel\",\"state\":\"COMPLETED\",\"name\":\"a\",\"workflow\":\"w\"}]"'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-failed" ]
}

@test "bucket=pending past timeout emits ci-timeout" {
  # gh exits 8 while checks are pending; shim mimics that.
  write_gh_shim 'printf "[{\"bucket\":\"pending\",\"state\":\"IN_PROGRESS\",\"name\":\"a\",\"workflow\":\"w\"}]"; exit 8'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-timeout" ]
}

@test "gh hard error (non-0, non-8) routes to ci-no-checks + captures stderr" {
  write_gh_shim 'echo "auth required" >&2; exit 4'
  run sh -c "$(cat "${SCRIPT}") 2>/dev/null"
  [ "${output}" = "ci-no-checks" ]
  # Stderr capture lets the ratchet distinguish "no checks" from "auth error".
  [ -f "${RUN_DIR}/poll_ci_error.txt" ]
  grep -q "gh pr checks exited 4" "${RUN_DIR}/poll_ci_error.txt"
  grep -q "auth required" "${RUN_DIR}/poll_ci_error.txt"
}

@test "non-numeric DEV_LOOP_CI_POLL_INTERVAL falls back to default + logs" {
  export DEV_LOOP_CI_POLL_INTERVAL=abc
  write_gh_shim 'printf "[{\"bucket\":\"pass\",\"state\":\"COMPLETED\",\"name\":\"a\",\"workflow\":\"w\"}]"'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ci-success" ]
  grep -q "invalid DEV_LOOP_CI_POLL_INTERVAL" "${RUN_DIR}/poll_ci_error.txt"
}

@test "zero DEV_LOOP_CI_POLL_INTERVAL falls back (no infinite tight loop)" {
  export DEV_LOOP_CI_POLL_INTERVAL=0
  write_gh_shim 'printf "[{\"bucket\":\"pass\",\"state\":\"COMPLETED\",\"name\":\"a\",\"workflow\":\"w\"}]"'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ci-success" ]
}

@test "no PR number emits ci-no-checks" {
  rm "${RUN_DIR}/pr_number.txt"
  write_gh_shim 'exit 0'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-no-checks" ]
}
