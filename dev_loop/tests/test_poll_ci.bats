#!/usr/bin/env bats
# test_poll_ci.bats — covers ci-success / ci-failed / ci-timeout / ci-no-checks.

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  rid="t-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  RUN_DIR="${DIP_ROOT}/runs/${rid}"
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

@test "all checks SUCCESS emits ci-success" {
  write_gh_shim 'printf "[{\"state\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]"'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-success" ]
}

@test "one FAILURE conclusion emits ci-failed" {
  write_gh_shim 'printf "[{\"state\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"},{\"state\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}]"'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-failed" ]
}

@test "checks still IN_PROGRESS past timeout emits ci-timeout" {
  write_gh_shim 'printf "[{\"state\":\"IN_PROGRESS\",\"conclusion\":null}]"'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-timeout" ]
}

@test "no PR number emits ci-no-checks" {
  rm "${RUN_DIR}/pr_number.txt"
  write_gh_shim 'exit 0'
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ci-no-checks" ]
}
