#!/usr/bin/env bats
# test_setup_run.bats — covers setup-ok, setup-resume-required, setup-failed.

setup() {
  load 'test_helpers'
  setup_env
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/setup_run.sh"
}

teardown() { rm -rf "${TMPDIR}"; }

@test "first run emits setup-ok and seeds .current_rid (from YAML)" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  [ -f "${DIP_ROOT}/.current_rid" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  [ -n "${rid}" ]
  [ -f "${DIP_ROOT}/runs/${rid}/env" ]
  grep -q "^GH_REPO='fixture-org/fixture-repo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
  grep -qF "GH_REPO=fixture-org/fixture-repo (source=yaml)" \
    "${DIP_ROOT}/runs/${rid}/config_resolution.txt"
}

@test "second run after cleanup allocates a fresh rid" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid_a="$(cat "${DIP_ROOT}/.current_rid")"
  # Mimic the pipeline reaching CleanupWorktree (releases the concurrency
  # lock). .current_rid persists; the next setup_run overwrites it atomically.
  CLEANUP="${BATS_TEST_DIRNAME}/../scripts/cleanup_worktree.sh"
  sh -c "$(cat "${CLEANUP}")" > /dev/null
  sleep 1
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid_b="$(cat "${DIP_ROOT}/.current_rid")"
  [ "${rid_a}" != "${rid_b}" ]
}

@test "concurrent setup_run (lock held) emits setup-lock-held (non-destructive route)" {
  # First setup_run claims the lock and exits successfully; the lock dir
  # remains because cleanup_worktree has not run yet (this is the very
  # early-phase window the lock exists to protect).
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid_a="$(cat "${DIP_ROOT}/.current_rid")"
  LOCK_DIR="${DIP_ROOT}/.dev_loop.lock"
  [ -d "${LOCK_DIR}" ]
  # bats's `run` uses a transient subshell, so the PID setup_run.sh wrote to
  # holder_pid (its $PPID, which IS that subshell) has already exited by now.
  # To model a real concurrent invocation — where tracker is still running —
  # overwrite holder_pid with the bats main process's PID, which IS guaranteed
  # alive for the duration of this test.
  printf '%s' "$$" > "${LOCK_DIR}/holder_pid"

  # A second setup_run starting in this window must emit `setup-lock-held` —
  # NOT `setup-failed`. The dip routes setup-lock-held straight to Exit (no
  # CleanupWorktree), because there's no worktree to clean for THIS invocation
  # and the .dev_loop_worktree symlink in cwd belongs to the OTHER live run.
  # .current_rid must stay pinned at rid_a so the first run keeps its RUN_DIR.
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-lock-held" ]
  rid_after="$(cat "${DIP_ROOT}/.current_rid")"
  [ "${rid_after}" = "${rid_a}" ]
}

@test "lock-held branch stays setup-lock-held even when run_dir mkdir fails" {
  # Defense-in-depth for #51: an unwritable runs/ dir at the moment a
  # second invocation hits the lock-contention branch must NOT trip the
  # EXIT trap (which would emit `setup-failed` and re-route through the
  # destructive CleanupWorktree). The mkdir + setup_error.txt redirect
  # are deliberately best-effort so the marker emission survives.
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  # First setup_run claims the lock cleanly.
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  LOCK_DIR="${DIP_ROOT}/.dev_loop.lock"
  printf '%s' "$$" > "${LOCK_DIR}/holder_pid"
  # Make runs/ read-only so the second invocation's lock-held branch can't
  # mkdir its own run_dir. Pre-fix, set -e would have tripped on the
  # unprotected mkdir and the trap would have emitted setup-failed.
  chmod 555 "${DIP_ROOT}/runs"
  run sh -c "$(cat "${SCRIPT}")"
  # Restore before teardown so rm -rf can clean up.
  chmod 755 "${DIP_ROOT}/runs"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-lock-held" ]
}

@test "prior worktree triggers setup-resume-required" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  mkdir -p "${DIP_ROOT}/runs/${rid}/worktree"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-resume-required" ]
}

@test "stale lock with dead holder_pid is reclaimed (not blocked on mtime)" {
  # Stage a lock dir whose holder_pid points at a process that has been dead
  # for a long time. The PID-based liveness check must let the next
  # setup_run reclaim the lock — even though the lock's mtime is fresh
  # (so the mtime fallback would have wrongly rejected). PID 1 (init) is
  # always alive, so we use a guaranteed-dead PID: a fresh `false` subshell.
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  mkdir -p "${DIP_ROOT}/.dev_loop.lock"
  # Spawn a short-lived child and capture its PID after it exits — that PID
  # is guaranteed dead by the time we check it.
  ( exec true ) &
  dead_pid=$!
  wait "${dead_pid}" 2>/dev/null || true
  printf '%s' "${dead_pid}" > "${DIP_ROOT}/.dev_loop.lock/holder_pid"
  printf 'stale-rid' > "${DIP_ROOT}/.dev_loop.lock/rid"

  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  [ "${rid}" != "stale-rid" ]
}

@test "missing .tracker/runs (no dip artifact dir) routes to setup-failed" {
  # Without staged .tracker/runs/<id>/, dip_artifact_dir resolves empty.
  # setup_run.sh must catch this and emit setup-failed with a clear message —
  # NOT write an env file with DIP_ARTIFACT_DIR unset and emit setup-ok (which
  # would later trip every persist_*.sh's env-present-but-DIP_ARTIFACT_DIR-
  # missing fail-closed gate).
  rm -rf "${WORKDIR}/.tracker"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Failure paths publish .current_rid so downstream cleanup/ratchet can find run_dir.
  run_dir="$(ls -d "${DIP_ROOT}/runs/"*/ | head -1)"
  grep -q "no dip artifact dir" "${run_dir%/}/setup_error.txt"
}

@test "missing tools route to setup-failed" {
  # Stage a PATH that contains the POSIX utilities setup_run.sh needs for its
  # own work (mkdir, cat, date, printf, ls, find, awk, kill, etc.) but
  # deliberately omits the dev_loop-required commands (gh, jq, git, tracker, yq).
  sysbin="${TMPDIR}/sysbin-only"
  mkdir -p "${sysbin}"
  for cmd in mkdir cat date printf ls find awk kill chmod rm cp mv tr \
             head sort uniq tail sed grep dash sh true false; do
    src=""
    if [ -x "/bin/${cmd}" ]; then src="/bin/${cmd}"
    elif [ -x "/usr/bin/${cmd}" ]; then src="/usr/bin/${cmd}"
    fi
    [ -n "${src}" ] && ln -sf "${src}" "${sysbin}/${cmd}"
  done

  run env -i HOME="${HOME}" XDG_CACHE_HOME="${XDG_CACHE_HOME}" \
      DEV_LOOP_STATE_ROOT="${DEV_LOOP_STATE_ROOT}" \
      PATH="${sysbin}" /bin/sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Failure paths publish .current_rid so downstream cleanup/ratchet can find run_dir.
  run_dir="$(ls -d "${DIP_ROOT}/runs/"*/ | head -1)"
  grep -q "missing required commands" "${run_dir%/}/setup_error.txt"
}

@test "wrong-variant yq (kislyuk) routes to setup-failed" {
  # Stage a yq shim that mimics kislyuk/yq's --version output (no "mikefarah" string).
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  cat > "${shim}/yq" <<'YQ'
#!/bin/sh
case $1 in
  --version) printf 'yq 3.4.3\n'; exit 0 ;;
  *) exit 1 ;;
esac
YQ
  chmod +x "${shim}/yq"
  PATH="${shim}:${PATH}" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Failure paths publish .current_rid so downstream cleanup/ratchet can find run_dir.
  run_dir="$(ls -d "${DIP_ROOT}/runs/"*/ | head -1)"
  grep -q "mikefarah" "${run_dir%/}/setup_error.txt"
}

@test "YAML repo loads when no env override" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^GH_REPO='test-org/test-repo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
  grep -qF "GH_REPO=test-org/test-repo (source=yaml)" \
    "${DIP_ROOT}/runs/${rid}/config_resolution.txt"
}

@test "env GH_REPO beats YAML" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: yaml-org/yaml-repo
base_branch: main
YAML
  GH_REPO=env-org/env-repo run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^GH_REPO='env-org/env-repo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
  grep -qF "GH_REPO=env-org/env-repo (source=env)" \
    "${DIP_ROOT}/runs/${rid}/config_resolution.txt"
}

@test "no repo configured (no env, no YAML) routes to setup-failed" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Failure paths publish .current_rid so downstream cleanup/ratchet can find run_dir.
  run_dir="$(ls -d "${DIP_ROOT}/runs/"*/ | head -1)"
  err="${run_dir%/}/setup_error.txt"
  grep -q "no repo configured" "${err}"
  grep -q "GH_REPO" "${err}"
  grep -q "dev_loop.config.yaml" "${err}"
}

@test "BASE_BRANCH autodetect via gh shim" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
YAML
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  # Mock gh repo view to return a non-default branch.
  cat > "${shim}/gh" <<'GH'
#!/bin/sh
case "$1 $2" in
  "repo view")
    if printf '%s\n' "$@" | grep -q defaultBranchRef; then
      printf 'develop\n'
      exit 0
    fi ;;
esac
exit 1
GH
  chmod +x "${shim}/gh"
  # Real yq/jq/git/tracker passthrough so prereq check passes.
  ln -sf "$(command -v yq)" "${shim}/yq" 2>/dev/null || true
  ln -sf "$(command -v jq)" "${shim}/jq" 2>/dev/null || true
  ln -sf "$(command -v git)" "${shim}/git" 2>/dev/null || true
  ln -sf "$(command -v tracker)" "${shim}/tracker" 2>/dev/null || true
  PATH="${shim}:${PATH}" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^BASE_BRANCH='develop'$" \
    "${DIP_ROOT}/runs/${rid}/env"
  grep -qF "BASE_BRANCH=develop (source=autodetect)" \
    "${DIP_ROOT}/runs/${rid}/config_resolution.txt"
}

@test "DEV_LOOP_BASE_BRANCH env beats YAML" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: master
YAML
  DEV_LOOP_BASE_BRANCH=feature/foo run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^BASE_BRANCH='feature/foo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
}

@test "atomic env write: env file mode 600, RUN_DIR mode 700, config_resolution.txt format" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
allow_no_ci: false
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  run_dir="${DIP_ROOT}/runs/${rid}"
  [ "$(stat -c %a "${run_dir}")" = "700" ]
  [ "$(stat -c %a "${run_dir}/env")" = "600" ]
  grep -qE '^GH_REPO=test-org/test-repo \(source=yaml\)$' "${run_dir}/config_resolution.txt"
  grep -qE '^BASE_BRANCH=main \(source=yaml\)$' "${run_dir}/config_resolution.txt"
  grep -qE '^ALLOW_NO_CI=false \(source=yaml\)$' "${run_dir}/config_resolution.txt"
}

@test "env file rejects YAML values containing newlines" {
  # YAML's double-quoted scalar `"foo\nbar"` decodes to a literal newline —
  # use the printf-literal `\\n` so YAML (not printf) does the escape.
  mkdir -p "${WORKDIR}/dev_loop/config"
  printf 'repo: "test/test"\nbase_branch: "foo\\nbar"\n' \
    > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Failure paths publish .current_rid so downstream cleanup/ratchet can find run_dir.
  run_dir="$(ls -d "${DIP_ROOT}/runs/"*/ | head -1)"
  grep -qi "newline" "${run_dir%/}/setup_error.txt"
}

@test "env file single-quotes values containing \$(...) and backticks" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: 'test/test'
base_branch: '$(rm -rf $HOME)'
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  ( set -a; . "${DIP_ROOT}/runs/${rid}/env"; set +a
    [ "${BASE_BRANCH}" = '$(rm -rf $HOME)' ] )
}

@test ".current_rid points at a complete env file (atomic publish)" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  run_dir="${DIP_ROOT}/runs/${rid}"
  # If .current_rid exists, env must exist and be a regular file.
  [ -f "${run_dir}/env" ]
  [ ! -L "${run_dir}/env" ]
  # No orphan tmp files.
  ! [ -e "${DIP_ROOT}/.current_rid.tmp" ]
  ! [ -e "${run_dir}/env.tmp" ]
}

@test "env file emits only allow-listed keys (drift guard vs comment block)" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"

  # Read the canonical allow-list from setup_run.sh's comment block.
  # The block is delimited by "Allow-list" header until the next `-----` line.
  allow=$(awk '/^# Allow-list/,/^# -+$/' "${SCRIPT}" \
    | tr -d '#' | tr -s ' \n' ' ' | tr ' ' '\n' \
    | grep -E '^[A-Z][A-Z0-9_]+$' | sort -u)
  [ -n "${allow}" ]

  # Every key emitted to env must be in the allow-list.
  emitted=$(awk -F= '/^[A-Z]/ {print $1}' "${DIP_ROOT}/runs/${rid}/env" | sort -u)
  for key in ${emitted}; do
    printf '%s\n' "${allow}" | grep -qx "${key}" \
      || { printf 'env emitted forbidden key: %s\n' "${key}" >&2; return 1; }
  done
}

@test "YAML runtime_state_root drives DIP_ROOT when env unset" {
  # Stage a YAML with a non-default runtime_state_root.
  mkdir -p "${WORKDIR}/dev_loop/config"
  custom_root="${TMPDIR}/yaml-state-root"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<YAML
repo: test-org/test-repo
base_branch: main
runtime_state_root: ${custom_root}
YAML
  # The helper exports DEV_LOOP_STATE_ROOT for test isolation; unset it
  # so the YAML.runtime_state_root branch is exercised.
  unset DEV_LOOP_STATE_ROOT
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  # Resolution: yaml_state_root + "/dev_loop"
  effective_root="${custom_root}/dev_loop"
  [ -f "${effective_root}/.current_rid" ]
  rid="$(cat "${effective_root}/.current_rid")"
  grep -qF "DIP_ROOT=${effective_root} (source=yaml)" \
    "${effective_root}/runs/${rid}/config_resolution.txt"
}

@test "setup_run writes .last_dip_root sentinel at the default location (#53)" {
  # The sentinel is the unified-resolution mechanism downstream bootstraps
  # use to follow YAML runtime_state_root without re-parsing YAML themselves.
  # It MUST land at the built-in default path so any bootstrap that runs with
  # no env override still finds it.
  mkdir -p "${WORKDIR}/dev_loop/config"
  custom_root="${TMPDIR}/yaml-state-root"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<YAML
repo: test-org/test-repo
base_branch: main
runtime_state_root: ${custom_root}
YAML
  unset DEV_LOOP_STATE_ROOT
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  default_root="${XDG_CACHE_HOME}/dip/dev_loop"
  [ -f "${default_root}/.last_dip_root" ]
  effective_root="${custom_root}/dev_loop"
  printf '%s' "${effective_root}" | cmp -s - "${default_root}/.last_dip_root"
}

@test "downstream bootstrap honors .last_dip_root sentinel (#53)" {
  # End-to-end smoke: drive YAML-only runtime_state_root override through to
  # a downstream node and confirm it resolves RUN_DIR without re-reading YAML.
  mkdir -p "${WORKDIR}/dev_loop/config"
  custom_root="${TMPDIR}/yaml-state-root"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<YAML
repo: test-org/test-repo
base_branch: main
runtime_state_root: ${custom_root}
YAML
  unset DEV_LOOP_STATE_ROOT
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  # Now invoke a downstream script with NO env override. Its bootstrap must
  # consult the sentinel (not the built-in default) to find .current_rid.
  CLEANUP="${BATS_TEST_DIRNAME}/../scripts/cleanup_worktree.sh"
  unset DEV_LOOP_STATE_ROOT DEV_LOOP_RUN_DIR
  run sh -c "$(cat "${CLEANUP}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-cleaned" ]
  # Sentinel content must equal the YAML-resolved DIP_ROOT (not the default).
  effective_root="${custom_root}/dev_loop"
  printf '%s' "${effective_root}" | cmp -s - "${XDG_CACHE_HOME}/dip/dev_loop/.last_dip_root"
}

@test "setup-failed under YAML-only root: cleanup_worktree still bootstraps (#53)" {
  # Regression: before the sentinel was published early, setup_run would
  # fail with YAML-redirected DIP_ROOT but leave .last_dip_root unset
  # (or stale), so cleanup_worktree (routed from setup-failed) looked
  # under the built-in default and died with "no .current_rid". The
  # sentinel must be published BEFORE any emit_failure path.
  mkdir -p "${WORKDIR}/dev_loop/config"
  custom_root="${TMPDIR}/yaml-state-root"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<YAML
repo: test-org/test-repo
base_branch: main
runtime_state_root: ${custom_root}
YAML
  # Force setup-failed deterministically (no gh network needed): remove the
  # tracker artifact dir so setup_run's "no dip artifact dir" path trips.
  rm -rf "${WORKDIR}/.tracker"
  unset DEV_LOOP_STATE_ROOT
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Sentinel must point at the YAML-resolved DIP_ROOT even on setup-failed.
  effective_root="${custom_root}/dev_loop"
  printf '%s' "${effective_root}" | cmp -s - "${XDG_CACHE_HOME}/dip/dev_loop/.last_dip_root"
  # cleanup_worktree (routed from setup-failed in dev_loop.dip) must
  # bootstrap cleanly and emit worktree-cleaned.
  CLEANUP="${BATS_TEST_DIRNAME}/../scripts/cleanup_worktree.sh"
  unset DEV_LOOP_STATE_ROOT DEV_LOOP_RUN_DIR
  run sh -c "$(cat "${CLEANUP}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-cleaned" ]
}

@test "sentinel write is non-fatal when XDG_CACHE_HOME is unwritable (YAML root succeeds)" {
  # If ~/.cache is read-only but the YAML-redirected DIP_ROOT is fine,
  # setup_run must NOT fail solely because it can't drop the sentinel
  # hint. Bootstraps without env override will fall back to the built-in
  # default (which is what they did pre-#53).
  mkdir -p "${WORKDIR}/dev_loop/config"
  custom_root="${TMPDIR}/yaml-state-root"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<YAML
repo: test-org/test-repo
base_branch: main
runtime_state_root: ${custom_root}
YAML
  # Pre-create XDG_CACHE_HOME and make it un-writable so publish_sentinel
  # gracefully no-ops. (mkdir -p must succeed on a pre-existing read-only
  # dir; the write itself is what we want to short-circuit.)
  mkdir -p "${XDG_CACHE_HOME}/dip/dev_loop"
  chmod a-w "${XDG_CACHE_HOME}/dip/dev_loop"
  unset DEV_LOOP_STATE_ROOT
  run sh -c "$(cat "${SCRIPT}")"
  chmod u+w "${XDG_CACHE_HOME}/dip/dev_loop"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  effective_root="${custom_root}/dev_loop"
  [ -f "${effective_root}/.current_rid" ]
}

@test "downstream bootstrap refuses symlinked .last_dip_root (parity with env-file)" {
  # The bootstrap refuses a symlinked run-dir env file. Same hardening for
  # the sentinel: an operator-tampered symlink at the sentinel path must
  # not be followed to an attacker-controlled destination. Downstream
  # falls back to the built-in default just like when the sentinel is
  # absent entirely.
  mkdir -p "${XDG_CACHE_HOME}/dip/dev_loop"
  # Plant a symlink at the sentinel path.
  ln -sfn /nonexistent/attacker-path "${XDG_CACHE_HOME}/dip/dev_loop/.last_dip_root"
  # Stage a run under the built-in default so the fallback resolves cleanly.
  unset DEV_LOOP_STATE_ROOT
  default_root="${XDG_CACHE_HOME}/dip/dev_loop"
  mkdir -p "${default_root}/runs/test-rid"
  printf 'test-rid' > "${default_root}/.current_rid"
  cat > "${default_root}/runs/test-rid/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
ALLOW_NO_CI='false'
DEV_LOOP_RUN_ID='test-rid'
DEV_LOOP_RUN_DIR='${default_root}/runs/test-rid'
DIP_ARTIFACT_DIR='${WORKDIR}/.tracker/runs/trk-$$'
DEV_LOOP_REPO_ROOT='${WORKDIR}'
EOF
  chmod 600 "${default_root}/runs/test-rid/env"
  CLEANUP="${BATS_TEST_DIRNAME}/../scripts/cleanup_worktree.sh"
  run sh -c "$(cat "${CLEANUP}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-cleaned" ]
}

@test "env DEV_LOOP_STATE_ROOT beats YAML runtime_state_root" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  yaml_root="${TMPDIR}/yaml-state-root"
  env_root="${TMPDIR}/env-state-root"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<YAML
repo: test-org/test-repo
base_branch: main
runtime_state_root: ${yaml_root}
YAML
  DEV_LOOP_STATE_ROOT="${env_root}" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ -f "${env_root}/.current_rid" ]
  rid="$(cat "${env_root}/.current_rid")"
  grep -qF "DIP_ROOT=${env_root} (source=env)" \
    "${env_root}/runs/${rid}/config_resolution.txt"
}

@test "BASE_BRANCH autodetect failure emits actionable setup-failed (not generic trap)" {
  # gh shim that mimics a network/auth failure (exit non-zero, no stdout).
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
YAML
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  cat > "${shim}/gh" <<'GH'
#!/bin/sh
printf 'gh: simulated auth failure\n' >&2
exit 1
GH
  chmod +x "${shim}/gh"
  ln -sf "$(command -v yq)" "${shim}/yq" 2>/dev/null || true
  ln -sf "$(command -v jq)" "${shim}/jq" 2>/dev/null || true
  ln -sf "$(command -v git)" "${shim}/git" 2>/dev/null || true
  ln -sf "$(command -v tracker)" "${shim}/tracker" 2>/dev/null || true
  ln -sf "$(command -v timeout)" "${shim}/timeout" 2>/dev/null || true
  PATH="${shim}:${PATH}" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  # The actionable emit_failure message must win over the generic trap.
  grep -q "base_branch autodetect failed" \
    "${DIP_ROOT}/runs/${rid}/setup_error.txt"
  # And the message names BOTH knobs the operator can flip.
  grep -q "DEV_LOOP_BASE_BRANCH" "${DIP_ROOT}/runs/${rid}/setup_error.txt"
  grep -q "YAML base_branch" "${DIP_ROOT}/runs/${rid}/setup_error.txt"
}

@test "malformed YAML routes to setup-failed with yq parse error" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  # Syntactically invalid YAML — unclosed flow sequence.
  printf 'repo: [unclosed\n' > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  [ -f "${DIP_ROOT}/runs/${rid}/setup_error.txt" ]
  # The error must point at the YAML somewhere (either yq's stderr or our
  # wrapping message that says "yq parse failed; see setup_error.txt").
  grep -qiE 'yq|parse|yaml' "${DIP_ROOT}/runs/${rid}/setup_error.txt"
}

@test "setup-failed publishes .current_rid so cleanup/ratchet can find run_dir" {
  # No YAML, no env → "no repo configured" path.
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # .current_rid must be published even on failure.
  [ -f "${DIP_ROOT}/.current_rid" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  [ -n "${rid}" ]
  # setup_error.txt is at the published run_dir.
  [ -f "${DIP_ROOT}/runs/${rid}/setup_error.txt" ]
  grep -q "no repo configured" "${DIP_ROOT}/runs/${rid}/setup_error.txt"
}

@test "setup-failed emit_failure writes \$run_dir/env (mode 600, only allow-listed keys)" {
  # No YAML, no env → "no repo configured" emit_failure path.
  # Every downstream script's bootstrap hard-requires $RUN_DIR/env to exist.
  # Without it, CleanupWorktree fails its own bootstrap before it can run,
  # and the pipeline halts on cleanup instead of routing through to RatchetLog.
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  run_dir="${DIP_ROOT}/runs/${rid}"
  [ -f "${run_dir}/env" ]
  [ ! -L "${run_dir}/env" ]
  [ "$(stat -c %a "${run_dir}/env")" = "600" ]
  # Each of the 6 allow-listed keys must be present (empty values OK for the
  # strings the failure path can't resolve).
  for key in GH_REPO BASE_BRANCH ALLOW_NO_CI DEV_LOOP_RUN_ID DEV_LOOP_RUN_DIR DIP_ARTIFACT_DIR; do
    grep -q "^${key}=" "${run_dir}/env" \
      || { printf 'missing key %s in emergency env\n' "${key}" >&2; return 1; }
  done
  # Sourcing must succeed and DEV_LOOP_RUN_DIR must round-trip to run_dir
  # (the bootstrap contract — cleanup/ratchet rely on this).
  ( set -a; . "${run_dir}/env"; set +a
    [ "${DEV_LOOP_RUN_DIR}" = "${run_dir}" ] )
}

@test "emergency env file sources cleanly when DIP_ROOT contains spaces" {
  # The emergency-env writer can't call sh_single_quote (PR #54's re-entrance
  # gap), but it must still emit a sourceable env file when DEV_LOOP_STATE_ROOT
  # — and hence the derived run_dir — contains a space. Unquoted KEY=value
  # under `set -a; . env; set +a` would split the value at whitespace and try
  # to run the tail as commands, breaking every downstream bootstrap.
  spaced_root="${TMPDIR}/with spaces/state"
  mkdir -p "${spaced_root}/runs"
  # No YAML, no GH_REPO → emit_failure's "no repo configured" path.
  DEV_LOOP_STATE_ROOT="${spaced_root}" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${spaced_root}/.current_rid")"
  run_dir="${spaced_root}/runs/${rid}"
  [ -f "${run_dir}/env" ]
  # The round-trip is the proof: source the file and confirm DEV_LOOP_RUN_DIR
  # equals the spaced run_dir verbatim. Pre-fix this returned only the prefix
  # up to the first space.
  ( set -a; . "${run_dir}/env"; set +a
    [ "${DEV_LOOP_RUN_DIR}" = "${run_dir}" ] \
      || { printf 'roundtrip mismatch: got=%s expected=%s\n' \
             "${DEV_LOOP_RUN_DIR}" "${run_dir}" >&2; return 1; } )
}

@test "EXIT-trap-driven setup-failed writes \$run_dir/env" {
  # Force an unexpected non-zero exit AFTER rid/run_dir are set: a yq shim
  # that satisfies the variant probe + the explicit emit_failure-wrapped
  # `.repo` query, then fails on the unwrapped `.base_branch` assignment
  # (set -e propagates → EXIT trap fires).
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
YAML
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  cat > "${shim}/yq" <<'YQ'
#!/bin/sh
case "$1" in
  --version) printf 'yq (https://github.com/mikefarah/yq/) version v4.40.0\n'; exit 0 ;;
  -r)
    case "$2" in
      .runtime_state_root*) printf '\n'; exit 0 ;;
      .repo*)              printf 'test-org/test-repo\n'; exit 0 ;;
      *)                   exit 99 ;;
    esac ;;
esac
exit 99
YQ
  chmod +x "${shim}/yq"
  ln -sf "$(command -v jq)" "${shim}/jq" 2>/dev/null || true
  ln -sf "$(command -v git)" "${shim}/git" 2>/dev/null || true
  ln -sf "$(command -v gh)" "${shim}/gh" 2>/dev/null || true
  ln -sf "$(command -v tracker)" "${shim}/tracker" 2>/dev/null || true
  ln -sf "$(command -v timeout)" "${shim}/timeout" 2>/dev/null || true
  PATH="${shim}:${PATH}" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  run_dir="${DIP_ROOT}/runs/${rid}"
  # The trap-written marker in setup_error.txt distinguishes it from emit_failure.
  grep -q "unexpected non-zero exit" "${run_dir}/setup_error.txt"
  # The trap must also have written the emergency env so CleanupWorktree's
  # bootstrap can source it. Same 6 keys + same mode as the emit_failure path.
  [ -f "${run_dir}/env" ]
  [ "$(stat -c %a "${run_dir}/env")" = "600" ]
  for key in GH_REPO BASE_BRANCH ALLOW_NO_CI DEV_LOOP_RUN_ID DEV_LOOP_RUN_DIR DIP_ARTIFACT_DIR; do
    grep -q "^${key}=" "${run_dir}/env" \
      || { printf 'missing key %s in trap-written env\n' "${key}" >&2; return 1; }
  done
}
