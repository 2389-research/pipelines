#!/usr/bin/env bats
# test_local_gates.bats — covers gates-pass / gates-fail with a real worktree.

setup() {
  load 'test_helpers'
  setup_env
  stage_run

  REPO="${TMPDIR}/repo"
  mkdir -p "${REPO}"
  cd "${REPO}"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  echo seed > README.md && git add README.md && git commit -q -m seed

  printf '%s' "${REPO}" > "${RUN_DIR}/worktree.path"

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
  git -C "${REPO}" checkout -q -b feature
  cat > "${REPO}/clean.dip" <<'EOF'
workflow test
  goal: "trivial"
  start: A
  exit: A
  agent A
    label: A
    max_turns: 1
    tool_access: none
EOF
  git -C "${REPO}" add clean.dip
  git -C "${REPO}" commit -q -m "add clean dip"

  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-pass" ]
}

@test "broken .dip on feature branch routes to gates-fail" {
  git -C "${REPO}" checkout -q -b feature
  cat > "${REPO}/broken.dip" <<'EOF'
workflow broken
  goal: "missing exit"
  start: A
  agent A
    prompt: hi
EOF
  git -C "${REPO}" add broken.dip
  git -C "${REPO}" commit -q -m "broken"

  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-fail" ]
  grep -q "dippin check failed" "${RUN_DIR}/gates_error.txt"
}

@test "missing worktree.path emits gates-fail" {
  rm "${RUN_DIR}/worktree.path"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-fail" ]
}

@test "local_gates no longer invokes tracker validate (#44)" {
  # Executor decoupling: dippin check (language-level) stays; tracker validate
  # (executor-level) is dropped. Stage a tracker stub that tattles via a
  # sentinel string and assert the sentinel never lands in gates_log.txt.
  git -C "${REPO}" checkout -q -b feature
  cat > "${REPO}/clean.dip" <<'EOF'
workflow test
  goal: "trivial"
  start: A
  exit: A
  agent A
    label: A
    max_turns: 1
    tool_access: none
EOF
  git -C "${REPO}" add clean.dip
  git -C "${REPO}" commit -q -m "add clean dip"

  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  cat > "${shim}/tracker" <<'TR'
#!/bin/sh
printf 'TRACKER_VALIDATE_SHOULD_NOT_RUN\n'
exit 0
TR
  chmod +x "${shim}/tracker"

  PATH="${shim}:${PATH}" run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-pass" ]
  # dippin check ran (its JSON output landed in the log).
  grep -q '"valid":true' "${RUN_DIR}/gates_log.txt"
  # tracker validate did NOT run (the stub's sentinel is absent).
  ! grep -q TRACKER_VALIDATE_SHOULD_NOT_RUN "${RUN_DIR}/gates_log.txt"
}

@test "local_gates tolerates absence of tracker on PATH (#44)" {
  # Porting payoff: operators on a non-tracker dip executor have no
  # `tracker` binary at all. gates-pass on a valid .dip must still land.
  git -C "${REPO}" checkout -q -b feature
  cat > "${REPO}/clean.dip" <<'EOF'
workflow test
  goal: "trivial"
  start: A
  exit: A
  agent A
    label: A
    max_turns: 1
    tool_access: none
EOF
  git -C "${REPO}" add clean.dip
  git -C "${REPO}" commit -q -m "add clean dip"

  # PATH with every binary local_gates needs (sh, git, dippin) but no tracker.
  sysbin="${TMPDIR}/sysbin-no-tracker"
  mkdir -p "${sysbin}"
  for cmd in sh dash cat printf mkdir rm chmod ln stat ls grep awk sed tr \
             head tail sort uniq find dirname basename git dippin; do
    src="$(command -v "${cmd}" 2>/dev/null || true)"
    [ -n "${src}" ] && ln -sf "${src}" "${sysbin}/${cmd}"
  done

  PATH="${sysbin}" run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-pass" ]
}
