#!/bin/sh
# ABOUTME: Guards the board's artifact ledger against drift: every state-dir file the subgraph body's shell
# ABOUTME: scripts write must be listed in board_artifact_files, so preflight excludes it and record scrubs it.
set -eu

kata_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
scripts="$kata_dir/scripts"
# shellcheck source=scripts/board-lib.sh
. "$scripts/board-lib.sh"

body="$kata_dir/board-item.dip"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' HUP INT TERM

board_artifact_files | sort >"$tmp/listed"

# The shell scripts and prompts the body reaches: scripts create the flat files beside selected.json, and
# the review/implement prompts tell the agents to write the rest. Read straight from board-item.dip so a
# renamed or dropped step updates both this check and the pipeline at once.
grep -oE 'scripts/[a-z-]+\.sh' "$body" | sort -u | sed "s#^#$kata_dir/#" >"$tmp/creators"
grep -oE '(scripts/[a-z-]+\.sh|prompts/[a-z-]+\.md)' "$body" | sort -u | sed "s#^#$kata_dir/#" >"$tmp/readers"

# No stale entry: every listed file must be named by some writer the body reaches, or the list has drifted
# from what the pipeline actually produces.
readers=$(cat "$tmp/readers")
while IFS= read -r f; do
  # shellcheck disable=SC2086
  grep -Fq -- "$f" $readers || {
    printf 'board-artifacts: %s is listed in board_artifact_files but no body writer names it\n' "$f" >&2
    exit 1
  }
done <"$tmp/listed"

# No silent escape: every "$base/<file>" literal a body script names must be a listed artifact, once the
# node-status directories (<Node>/status.json) and transient .tmp siblings are set aside. A new script
# artifact that skips board_artifact_files trips here instead of leaking into the operator's repo.
: >"$tmp/written"
while IFS= read -r creator; do
  grep -oE '\$\{?base\}?/[A-Za-z0-9._/-]+' "$creator" >>"$tmp/written" || true
done <"$tmp/creators"
sed -E 's#^\$\{?base\}?/##; s#\.tmp$##' "$tmp/written" | sort -u >"$tmp/written.norm"
while IFS= read -r rel; do
  case "$rel" in ''|*/status.json) continue ;; esac
  grep -Fxq -- "$rel" "$tmp/listed" || {
    printf 'board-artifacts: a body script writes the state-dir file %s, which is not in board_artifact_files\n' "$rel" >&2
    exit 1
  }
done <"$tmp/written.norm"

printf 'board-artifacts: ok\n'
