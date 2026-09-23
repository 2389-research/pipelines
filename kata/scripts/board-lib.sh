# shellcheck shell=sh
# ABOUTME: Shared board helpers: the workspace-root paths the subgraph body creates, plus a run-id suffix.
# ABOUTME: One source of truth for board-preflight.sh (exclude + guard) and board-record.sh (scrub).

# The marker constants below are read by the scripts that source this file, not within it.
# shellcheck disable=SC2034
# Markers around the board's block in .git/info/exclude; preflight adds the block, record removes it.
BOARD_EXCLUDE_BEGIN='# BEGIN kata board managed excludes'
BOARD_EXCLUDE_END='# END kata board managed excludes'

# Node names from the subgraph body dip. Tracker writes a <name>/status.json directory per node at the
# workspace root, so both scripts treat these as directories to hide and to scrub.
board_node_names() {
  awk '$1 ~ /^(tool|agent|parallel|fan_in|human|subgraph)$/ {print $2}' "$1"
}

# Files the body writes beside selected.json (STATE_PATH), which in subgraph mode is the workspace root:
# claim-next.sh writes selected.json; the implement/repair/review prompts write verification.txt,
# completion.md, and the two .approved files; handoff-selected.sh writes handoff.md, handoff-comment.md,
# and handoff.json; continue-implement.sh writes continue-implement.json. tests/board-artifacts.sh
# cross-checks this list against those writers so a new script artifact cannot silently escape the
# excludes and the scrub, and a dropped writer cannot leave a stale entry behind.
board_artifact_files() {
  cat <<'EOF'
selected.json
verification.txt
completion.md
review-correctness.approved
review-scope.approved
handoff.md
handoff-comment.md
handoff.json
question.md
continue-implement.json
EOF
}

# Six random hex characters. Each sweep gets a fresh run-id suffix so a reclaimed kata lands on a new
# branch name instead of colliding with the branch a previous sweep left behind.
board_rand6() {
  od -An -N3 -tx1 /dev/urandom | tr -d ' \n'
}
