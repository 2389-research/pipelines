#!/usr/bin/env bats
# test_init_iter_counter.bats

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  rid="t-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  RUN_DIR="${DIP_ROOT}/runs/${rid}"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/init_iter_counter.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "init writes iter=1 and max_iters" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "iter-init-ok" ]
  [ "$(cat "${RUN_DIR}/iter.txt")" = "1" ]
  [ -f "${RUN_DIR}/max_iters.txt" ]
}

@test "init without rid sentinel exits non-zero" {
  rm "${DIP_ROOT}/.current_rid"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -ne 0 ]
}
