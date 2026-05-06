#!/bin/sh
# Generate .ai/ledger.tsv from existing .ai/sprints/SPRINT-*.md files.
# Every sprint starts marked `planned`. Edit column 3 to `completed` for
# any sprint already shipped if you're bootstrapping mid-project.
#
# Run from the project root (the directory that contains .ai/sprints/).
set -eu

if [ ! -d .ai/sprints ]; then
  echo "no .ai/sprints/ directory in $(pwd)" >&2
  exit 1
fi

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p .ai

{
  printf 'sprint_id\ttitle\tstatus\tcreated_at\tupdated_at\n'
  for f in .ai/sprints/SPRINT-*.md; do
    [ -f "$f" ] || continue
    id=$(basename "$f" .md | sed 's/SPRINT-//')
    # First non-empty heading line, with the "Sprint NNN — " prefix stripped (handles em-dash / en-dash / hyphen).
    title=$(awk '/^#/ {print; exit}' "$f" \
      | sed 's/^#\{1,\} *//' \
      | sed -E 's/^[Ss]print *[0-9]+ *([—–-] *)?//' \
      | tr -d '\t')
    printf '%s\t%s\tplanned\t%s\t%s\n' "$id" "$title" "$now" "$now"
  done
} > .ai/ledger.tsv

count=$(awk 'NR>1' .ai/ledger.tsv | wc -l | tr -d ' ')
echo "wrote .ai/ledger.tsv with $count sprints (all marked planned)"
echo
cat .ai/ledger.tsv
