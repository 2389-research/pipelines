#!/usr/bin/env bats
# test_fetch_open_issues.bats — covers fetched-ok and fetch-failed.
# Uses a PATH shim to mock `gh` without hitting the network.

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/fetch_open_issues.sh"
  FIXTURE="${BATS_TEST_DIRNAME}/fixtures/issues_sample.json"
  rid="t-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  printf 'GH_REPO=2389-research/pipelines\n' > "${DIP_ROOT}/runs/${rid}/env"
  RUN_DIR="${DIP_ROOT}/runs/${rid}"

  # PATH shim directory.
  SHIM="${TMPDIR}/bin"
  mkdir -p "${SHIM}"
  export PATH="${SHIM}:${PATH}"
}

teardown() {
  rm -rf "${TMPDIR}"
}

write_gh_shim() {
  cat > "${SHIM}/gh" <<EOF
#!/usr/bin/env bash
$1
EOF
  chmod +x "${SHIM}/gh"
}

@test "fetched-ok writes issues.json + count" {
  write_gh_shim "cat '${FIXTURE}'; exit 0"
  run sh -c "sh -c \"\$(cat '${SCRIPT}')\" 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ "${output}" = "fetched-ok" ]
  [ -f "${RUN_DIR}/issues.json" ]
  [ "$(cat "${RUN_DIR}/issues_count.txt")" = "6" ]
}

@test "gh failure routes to fetch-failed" {
  write_gh_shim "echo 'gh: rate limited' >&2; exit 4"
  run sh -c "sh -c \"\$(cat '${SCRIPT}')\" 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ "${output}" = "fetch-failed" ]
  grep -q "gh issue list failed" "${RUN_DIR}/fetch_error.txt"
}

@test "malformed JSON from gh fails closed to fetch-failed" {
  write_gh_shim "printf 'this is not json\n'"
  run sh -c "sh -c \"\$(cat '${SCRIPT}')\" 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ "${output}" = "fetch-failed" ]
  grep -q "jq parse failed" "${RUN_DIR}/fetch_error.txt"
}

@test "missing rid sentinel routes to fetch-failed" {
  rm "${DIP_ROOT}/.current_rid"
  write_gh_shim "exit 0"
  run sh -c "sh -c \"\$(cat '${SCRIPT}')\" 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ "${output}" = "fetch-failed" ]
}
