#!/bin/sh
# ABOUTME: Build deterministic .dipx bundles for the three top-level _dr pipelines.
# ABOUTME: Output: dist/<pipeline>.dipx (gitignored — reproducible from .dip sources).
#
# Usage:
#   scripts/pack.sh           # pack all three
#   scripts/pack.sh runner    # pack just sprint_runner_dr (also bundles exec + spec_to_sprints subgraphs)
#   scripts/pack.sh exec      # pack just sprint_exec_dr (and its parts/* subgraphs)
#   scripts/pack.sh spec      # pack just spec_to_sprints_dr
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
mkdir -p "$DIST_DIR"

pack_one() {
  ENTRY="$1"
  OUT="$DIST_DIR/$(basename "$ENTRY" .dip).dipx"
  cd "$REPO_ROOT"
  dippin pack --dry-run "$ENTRY" >/dev/null
  dippin pack -o "$OUT" "$ENTRY"
  IDENTITY=$(dippin inspect "$OUT" | awk '/^identity:/{print $2}')
  printf '  %-32s %s\n' "$(basename "$OUT")" "$IDENTITY"
}

WHICH="${1:-all}"
case "$WHICH" in
  all)
    echo "→ packing all three _dr pipelines into $DIST_DIR/"
    pack_one sprint_runner_dr.dip
    pack_one sprint_exec_dr.dip
    pack_one spec_to_sprints_dr.dip
    ;;
  runner) pack_one sprint_runner_dr.dip ;;
  exec)   pack_one sprint_exec_dr.dip ;;
  spec)   pack_one spec_to_sprints_dr.dip ;;
  *)
    echo "unknown target: $WHICH (use: all|runner|exec|spec)" >&2
    exit 1
    ;;
esac
