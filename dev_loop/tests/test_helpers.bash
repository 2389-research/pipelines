# dev_loop/tests/test_helpers.bash — shared bats test fixture helper.
#
# Exports ONE function: setup_env().
#
# Conventions:
# - DIP_ROOT (test-side) is an inspection alias for DEV_LOOP_STATE_ROOT
#   (script-side). Scripts honor DEV_LOOP_STATE_ROOT; tests use DIP_ROOT
#   to assert on staged paths. Both point at the same TMPDIR-anchored dir.
# - The unset list mirrors setup_run.sh's emit allow-list (canonical home is
#   the comment block immediately above emit_env() in scripts/setup_run.sh).
#   When you add an env-honored knob, update BOTH places.
# - HOME and XDG_CONFIG_HOME are sandboxed to TMPDIR so tests don't leak the
#   developer's gh auth into the test environment.
#
# Conventional bats usage:
#   setup() {
#     load 'test_helpers'
#     setup_env
#     SCRIPT="${BATS_TEST_DIRNAME}/../scripts/<name>.sh"
#   }
#   teardown() { rm -rf "${TMPDIR}"; }

setup_env() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  export HOME="${TMPDIR}/home"
  mkdir -p "${HOME}"
  export DEV_LOOP_STATE_ROOT="${TMPDIR}/state"
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"
  unset GH_REPO GH_HOST GH_TOKEN GITHUB_TOKEN \
        GH_CONFIG_DIR XDG_CONFIG_HOME \
        DEV_LOOP_BASE_BRANCH DEV_LOOP_ALLOW_NO_CI DEV_LOOP_RUN_DIR \
        DEV_LOOP_CI_POLL_INTERVAL DEV_LOOP_CI_POLL_TIMEOUT
  WORKDIR="${TMPDIR}/workdir"
  mkdir -p "${WORKDIR}/.tracker/runs/trk-$$"
  cd "${WORKDIR}"
  mkdir -p "${DIP_ROOT}/runs"
}
