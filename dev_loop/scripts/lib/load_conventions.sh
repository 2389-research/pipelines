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
  _conv_path=""
  if [ -n "${DEV_LOOP_CONVENTIONS_FILE:-}" ] && [ -f "${DEV_LOOP_CONVENTIONS_FILE}" ]; then
    _conv_path="${DEV_LOOP_CONVENTIONS_FILE}"
  elif [ -f "./.dev_loop/conventions.md" ]; then
    _conv_path="./.dev_loop/conventions.md"
  elif [ -f "./AGENTS.md" ]; then
    _conv_path="./AGENTS.md"
  elif [ -f "./CLAUDE.md" ]; then
    _conv_path="./CLAUDE.md"
  elif [ -f "./CONVENTIONS.md" ]; then
    _conv_path="./CONVENTIONS.md"
  elif [ -f "dev_loop/config/repo_conventions.md" ]; then
    _conv_path="dev_loop/config/repo_conventions.md"
  fi
  if [ -n "${_conv_path}" ]; then
    CONVENTIONS_TEXT=$(cat "${_conv_path}")
  else
    CONVENTIONS_TEXT='(no conventions found; reviewers, fall back to general programming sense and the plan + diff)'
  fi
  unset _conv_path
}
