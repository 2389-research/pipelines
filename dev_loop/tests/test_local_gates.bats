#!/usr/bin/env bats
# test_local_gates.bats — covers gates-pass / gates-fail with a real worktree.

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  rid="t-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  RUN_DIR="${DIP_ROOT}/runs/${rid}"

  WORKDIR="${TMPDIR}/repo"
  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  echo seed > README.md && git add README.md && git commit -q -m seed

  printf '%s' "${WORKDIR}" > "${RUN_DIR}/worktree.path"

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/local_gates.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "no changed .dips means gates-pass" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-pass" ]
}

@test "valid added .dip on feature branch lets gates pass" {
  git -C "${WORKDIR}" checkout -q -b feature
  cat > "${WORKDIR}/clean.dip" <<'EOF'
workflow test
  goal: "trivial"
  start: A
  exit: A
  agent A
    label: A
    max_turns: 1
    tool_access: none
EOF
  git -C "${WORKDIR}" add clean.dip
  git -C "${WORKDIR}" commit -q -m "add clean dip"

  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-pass" ]
}

@test "broken .dip on feature branch routes to gates-fail" {
  git -C "${WORKDIR}" checkout -q -b feature
  cat > "${WORKDIR}/broken.dip" <<'EOF'
workflow broken
  goal: "missing exit"
  start: A
  agent A
    prompt: hi
EOF
  git -C "${WORKDIR}" add broken.dip
  git -C "${WORKDIR}" commit -q -m "broken"

  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-fail" ]
  grep -q "dippin check failed" "${RUN_DIR}/gates_error.txt"
}

@test "missing worktree.path emits gates-fail" {
  rm "${RUN_DIR}/worktree.path"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-fail" ]
}
