# load_conventions.sh — POSIX sh helper resolving the conventions text.
#
# Sourced (NOT executed) by tool scripts that include a <repo_conventions>
# block in the implementer/squad prompt context. Sets CONVENTIONS_TEXT in
# the caller's scope.
#
# Precedence (first hit wins):
#   1. ${DEV_LOOP_CONVENTIONS_FILE}      env explicit
#   2. ./.dev_loop/conventions.md        operator-curated
#   3. ./AGENTS.md                       cross-tool standard
#   4. ./CLAUDE.md                       Anthropic-adjacent repos
#   5. ./CONVENTIONS.md                  generic
#   6. dev_loop/config/repo_conventions.md  shipped template
#   7. empty stub                        no conventions found

load_conventions() {
  CONVENTIONS_TEXT=""
  # Resolve relative cascade entries against the repo top-level when
  # available, so callers running from a subdirectory still hit
  # AGENTS.md / .dev_loop/conventions.md / etc. Falls back to cwd if
  # git isn't available or we're not in a repo.
  _conv_root="${DEV_LOOP_REPO_ROOT:-}"
  if [ -z "${_conv_root}" ] && command -v git >/dev/null 2>&1; then
    _conv_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  fi
  [ -n "${_conv_root}" ] || _conv_root="."

  # Walk the cascade with a -r (readable) test. A file that exists but is
  # unreadable (chmod 000) must NOT abort the run — fall through to the
  # next entry. The env override is checked with -r as well so an
  # operator typo doesn't poison the cascade.
  _conv_path=""
  if [ -n "${DEV_LOOP_CONVENTIONS_FILE:-}" ] && [ -r "${DEV_LOOP_CONVENTIONS_FILE}" ]; then
    _conv_path="${DEV_LOOP_CONVENTIONS_FILE}"
  elif [ -r "${_conv_root}/.dev_loop/conventions.md" ]; then
    _conv_path="${_conv_root}/.dev_loop/conventions.md"
  elif [ -r "${_conv_root}/AGENTS.md" ]; then
    _conv_path="${_conv_root}/AGENTS.md"
  elif [ -r "${_conv_root}/CLAUDE.md" ]; then
    _conv_path="${_conv_root}/CLAUDE.md"
  elif [ -r "${_conv_root}/CONVENTIONS.md" ]; then
    _conv_path="${_conv_root}/CONVENTIONS.md"
  elif [ -r "${_conv_root}/dev_loop/config/repo_conventions.md" ]; then
    _conv_path="${_conv_root}/dev_loop/config/repo_conventions.md"
  fi
  if [ -n "${_conv_path}" ]; then
    # Non-fatal read: if a race (or unusual filesystem error) makes the
    # file unreadable between the -r check and the cat, fall back to the
    # stub rather than aborting the calling tool under `set -e`.
    CONVENTIONS_TEXT=$(cat "${_conv_path}" 2>/dev/null || true)
  fi
  if [ -z "${CONVENTIONS_TEXT}" ]; then
    CONVENTIONS_TEXT='(no conventions found; reviewers, fall back to general programming sense and the plan + diff)'
  fi
  unset _conv_path _conv_root
}
