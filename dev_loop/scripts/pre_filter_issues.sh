#!/bin/sh
# pre_filter_issues.sh — deterministic filter applied to the fetched issue list.
# Emits: filter-ok | filter-empty | filter-failed
#
# Filter rules (mirror config/dev_loop.config.yaml):
#   - drop excluded_labels (default: survey, question, tracking, blocked)
#   - drop authors matching '*[bot]' glob
#   - drop excluded title patterns (default: dev_loop / dippin meta / tracker meta)
#   - sort by priority_label (P0 > P1 > P2 > P3 > unlabeled) then issue_number ASC
#
# Outputs:
#   $RUN_DIR/filtered_issues.json   — survivors, sorted by descending priority
#   $RUN_DIR/filter_count.txt       — integer count
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'filter-failed'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"

emit_failure() {
  mkdir -p "${RUN_DIR}" 2>/dev/null || true
  printf '%s\n' "$1" > "${RUN_DIR}/filter_error.txt" 2>/dev/null || true
  printf 'filter-failed'
  exit 0
}

trap 'if [ $? -ne 0 ]; then printf "filter-failed"; exit 0; fi' EXIT

if [ ! -f "${RUN_DIR}/issues.json" ]; then
  emit_failure "issues.json missing"
fi

# Filter knobs MUST match config/dev_loop.config.yaml defaults.
EXCLUDED_LABELS='["survey","question","tracking","blocked"]'
EXCLUDED_TITLE_RE='(dev_loop|dippin meta|tracker meta)'

jq --argjson excluded "${EXCLUDED_LABELS}" \
   --arg title_re "${EXCLUDED_TITLE_RE}" '
  def priority_rank:
    ((.labels // []) | map(.name)) as $names
    | if   ($names | index("P0")) then 0
      elif ($names | index("P1")) then 1
      elif ($names | index("P2")) then 2
      elif ($names | index("P3")) then 3
      else 4
      end;
  map(select(
    (((.labels // []) | map(.name)) as $names
       | ($names | map(. as $l | $excluded | index($l)) | all(. == null)))
    and ((.author.login // "") | test("\\[bot\\]$") | not)
    and ((.title // "") | test($title_re; "i") | not)
  ))
  | sort_by(priority_rank, .number)
' "${RUN_DIR}/issues.json" > "${RUN_DIR}/filtered_issues.json.tmp" \
  || emit_failure "jq filter failed"

count=$(jq 'length' "${RUN_DIR}/filtered_issues.json.tmp")
mv "${RUN_DIR}/filtered_issues.json.tmp" "${RUN_DIR}/filtered_issues.json"
printf '%s' "${count}" > "${RUN_DIR}/filter_count.txt"

if [ "${count}" -eq 0 ]; then
  printf 'filter-empty'
  exit 0
fi

# Emit marker first; SelectNextIssue agent (tool_access: none) reads the
# filtered issue list via ctx.last_response (auto-injected into its prompt).
# Anthropic/Gemini prompt guidance both recommend XML tags over text fences
# for parser reliability with long-context structured inputs.
printf 'filter-ok'
issues_text=$(cat "${RUN_DIR}/filtered_issues.json")
cat <<DATA

<filtered_issues>
${issues_text}
</filtered_issues>
DATA
