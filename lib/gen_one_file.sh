#!/usr/bin/env bash
# gen_one_file.sh — call qwen3.6:35b-a3b-q8_0 to generate ONE file per invocation.
# Mirrors the gen_file logic from sprint_runner_local_gen_qwen_sr.dip (Generate node)
# so we can iterate file-by-file and inspect each output before continuing.
#
# Usage (run from inside the sprint workdir):
#   bash pipelines/lib/gen_one_file.sh <filepath>                       # uses .ai/sprints/SPRINT-001.md
#   bash pipelines/lib/gen_one_file.sh <filepath> <sprint_doc>          # explicit sprint doc
#
# Examples:
#   bash $PIPELINES_REPO/lib/gen_one_file.sh backend/app/config.py
#   bash $PIPELINES_REPO/lib/gen_one_file.sh backend/tests/conftest.py .ai/sprints/SPRINT-001.md
#
# Behavior:
# - If the file's bullet description in `## New files` matches /^(empty|blank|placeholder|marker)/i,
#   `touch` the file and exit (no LLM call).
# - Otherwise, call qwen via Ollama HTTP API with the official recipe params (Generate-initial profile:
#   temp=1.0, top_p=0.95, top_k=20, min_p=0, presence_penalty=1.5) and write the response to the file.
# - Strip leading/trailing markdown fences from the response.
# - Run a syntax check for Python/Go/JS files; on failure, retry once at temp=0.6 (precise-edit profile).
# - Print a one-line summary on stdout.
#
# Exit codes:
#   0 — file written and (if applicable) passes syntax check
#   1 — bad arguments / sprint doc missing / curl failure
#   2 — file written but syntax check still fails after retry

set -u

FILEPATH="${1:-}"
SPRINT_DOC="${2:-.ai/sprints/SPRINT-001.md}"
OLLAMA="${OLLAMA_URL:-http://localhost:11434/api/chat}"
MODEL="${QWEN_MODEL:-qwen3.6:35b-a3b-q8_0}"
MAX_TOKENS="${MAX_TOKENS:-4096}"

if [ -z "$FILEPATH" ]; then
  echo "usage: $0 <filepath> [<sprint_doc>]" >&2
  exit 1
fi
if [ ! -f "$SPRINT_DOC" ]; then
  echo "error: sprint doc not found: $SPRINT_DOC" >&2
  exit 1
fi

SPRINT=$(cat "$SPRINT_DOC")
SYS="You are a code generator. Output only the raw file content. No explanation, no markdown fences, no commentary."

# Find this file's bullet (if any) in `## New files` and `## Modified files`.
# Bullet format: `- \`path/to/file\` — description`
DESCRIPTION=$(awk -v target="$FILEPATH" '
  /^## (New files|Modified files)/ {f=1; next}
  f && /^##/ {f=0}
  f {
    if (match($0, /`[^`]+`/)) {
      bt=substr($0, RSTART+1, RLENGTH-2)
      if (bt == target) { print substr($0, RSTART+RLENGTH); exit }
    }
  }
' "$SPRINT_DOC" | sed -E 's/^[[:space:]]*[—-][[:space:]]*//')

if [ -z "$DESCRIPTION" ]; then
  DESCRIPTION='Implement exactly as specified in the sprint. Use the Interface contract, Algorithm notes, Imports per file, and Test plan sections for this file.'
fi

# Empty-file shortcut: description starts with empty/blank/placeholder/marker.
if echo "$DESCRIPTION" | grep -qiE '^[[:space:]]*(empty|blank|placeholder|marker)'; then
  mkdir -p "$(dirname "$FILEPATH")" 2>/dev/null || true
  : > "$FILEPATH"
  echo "touched $FILEPATH (empty marker — no LLM call)"
  exit 0
fi

call_qwen() {
  # $1 = temperature, $2 = presence_penalty
  local temp="$1"; local ppen="$2"
  local user_msg="CONTRACT (full spec):

${SPRINT}

GENERATE THIS FILE: ${FILEPATH}
${DESCRIPTION}

Output ONLY the raw file content. Nothing else."
  curl -sf "$OLLAMA" \
    -H 'Content-Type: application/json' \
    --data "$(jq -n \
      --arg model "$MODEL" \
      --arg sys "$SYS" \
      --arg msg "$user_msg" \
      --argjson temp "$temp" \
      --argjson ppen "$ppen" \
      --argjson tokens "$MAX_TOKENS" \
      '{model:$model,think:false,stream:false,
        messages:[{role:"system",content:$sys},{role:"user",content:$msg}],
        options:{temperature:$temp,top_p:0.95,top_k:20,min_p:0,presence_penalty:$ppen,num_ctx:32768,num_predict:$tokens}}')" \
    | jq -r '.message.content'
}

syntax_check() {
  local fp="$1"
  case "$fp" in
    *.py)      python3 -m py_compile "$fp" 2>&1 ;;
    *.go)      gofmt -e "$fp" >/dev/null 2>&1 || gofmt -e "$fp" 2>&1 ;;
    *.ts|*.js) node --check "$fp" 2>&1 ;;
    *)         echo "" ;;  # no syntax check for this filetype
  esac
}

mkdir -p "$(dirname "$FILEPATH")" 2>/dev/null || true

# First attempt: Generate-initial profile (temp=1.0, presence_penalty=1.5)
echo "generating $FILEPATH ..." >&2
RESPONSE=$(call_qwen 1.0 1.5)
if [ -z "$RESPONSE" ]; then
  echo "error: empty response from $OLLAMA" >&2
  exit 1
fi
# Strip leading/trailing markdown fences
echo "$RESPONSE" | sed '/^```/d' > "$FILEPATH"
BYTES=$(wc -c < "$FILEPATH" | tr -d ' ')
echo "wrote $FILEPATH ($BYTES bytes, temp=1.0)" >&2

# Syntax check
ERR=$(syntax_check "$FILEPATH")
if [ -n "$ERR" ]; then
  echo "syntax error in $FILEPATH:" >&2
  echo "$ERR" | head -5 >&2
  echo "retrying at temp=0.6 ..." >&2
  RESPONSE=$(call_qwen 0.6 0.0)
  if [ -n "$RESPONSE" ]; then
    echo "$RESPONSE" | sed '/^```/d' > "$FILEPATH"
    BYTES=$(wc -c < "$FILEPATH" | tr -d ' ')
    echo "rewrote $FILEPATH ($BYTES bytes, temp=0.6)" >&2
    ERR=$(syntax_check "$FILEPATH")
    if [ -n "$ERR" ]; then
      echo "WARN: $FILEPATH still has syntax errors after retry:" >&2
      echo "$ERR" | head -5 >&2
      exit 2
    fi
  fi
fi

echo "OK $FILEPATH"
exit 0
