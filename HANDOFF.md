# Handoff: Organize .dip files into project directories

## Task
Move all .dip files from repo root into themed project directories. Add README to each.

## Approved Grouping (Doctor Biz confirmed)

- `build-and-ship/` — speedrun, build_from_superpowers, bug-hunter, refactor-express, doc-writer
- `sprint/` — spec_to_sprints (+ yaml, yaml_v2), sprint_exec (+ cheap, yaml, yaml_v2), sprint_runner (+ cheap, yaml, yaml_v2), spec_to_ship_yaml, megaplan
- `pipeline-gen/` — spec_to_dip, pipeline_from_spec (+ v2), pipeline_from_superpowers
- `interactive/` — 20q, story-engine, model-debate, debate-log.md
- `greenfield/` — greenfield, greenfield_discovery, greenfield_review, greenfield_synthesis, greenfield_validation
- `iterative/` — iter_run, iter_audit, iter_dev, iter_scope, iter_extract

## Next Steps
1. `mkdir -p build-and-ship sprint pipeline-gen interactive greenfield iterative`
2. `git mv` each group (see commands below)
3. Write README.md in each directory with descriptions from root README
4. Update root README.md paths from `file.dip` to `dir/file.dip`

## Commands
```bash
cd /Users/harper/Public/src/2389/pipelines
mkdir -p build-and-ship sprint pipeline-gen interactive greenfield iterative
git mv speedrun.dip build_from_superpowers.dip bug-hunter.dip refactor-express.dip doc-writer.dip build-and-ship/
git mv spec_to_sprints.dip spec_to_sprints_yaml.dip spec_to_sprints_yaml_v2.dip sprint_exec.dip sprint_exec-cheap.dip sprint_exec_yaml.dip sprint_exec_yaml_v2.dip sprint_runner.dip sprint_runner-cheap.dip sprint_runner_yaml.dip sprint_runner_yaml_v2.dip spec_to_ship_yaml.dip megaplan.dip sprint/
git mv spec_to_dip.dip pipeline_from_spec.dip pipeline_from_spec_v2.dip pipeline_from_superpowers.dip pipeline-gen/
git mv 20q.dip story-engine.dip model-debate.dip debate-log.md interactive/
git mv greenfield.dip greenfield_discovery.dip greenfield_review.dip greenfield_synthesis.dip greenfield_validation.dip greenfield/
git mv iter_run.dip iter_audit.dip iter_dev.dip iter_scope.dip iter_extract.dip iterative/
```

## README descriptions
- build-and-ship: Single-pass build pipelines — fastest path from spec/bug to shipped code
- sprint: Sprint decomposition and execution with budget and YAML variants
- pipeline-gen: Meta-pipelines generating .dip files from specs via multi-model tournament
- interactive: Human-in-the-loop games and debates
- greenfield: New project validation — discovery, synthesis, review, validation
- iterative: Incremental dev with PAR review gates — scope, extract, dev, run, audit

## Notes
- docs/simmer/*.dip are iteration artifacts — leave in place
- Branch: feat/iterative-dev-pipelines
- After reorg, update subgraph refs in iter_dev.dip (ref: iter_extract.dip → ref: iterative/iter_extract.dip etc.) IF iter_dev.dip uses relative paths
- sprint_exec_yaml_v2.dip has UNCOMMITTED unrelated changes — stage carefully

## Outstanding iter_* Design Issues (separate work from reorg)
Decisions made so far:
- #3 PAR differentiation: DONE (committed 0851cd2)
- #10 TDD red phase: Option C — prompt-only, no structural gate
- #11 TBD scenarios: Option C — DONE (committed 0c17ee3, structural gate + prompt reinforcement)
- #15 Flash aggregators: Option C — keep as-is, mechanical merge is fine for Flash

Still need Doctor Biz decisions:
- #17: Loop feedback absent (restart loops lack prior-attempt context)
  - Options: (a) tool node writes failure reason to .ai/loop-context.txt before restart, agent reads it (b) accept, max_restarts caps it
- #19-22: Missing spec nodes (classify_chunks, build_coverage_ledger, patch_extractions loop, 4 implementer statuses)
  - Options: (a) add missing nodes (b) update spec to match impl (c) mix

## Recent Commits on feat/iterative-dev-pipelines
- 0c17ee3 feat(iter_audit): add TBD scenario gate and reviewer prompt reinforcement
- 0851cd2 feat: differentiate all 16 PAR reviewer prompts and assign specialist models
- 9c57fb8 fix: address expert panel review findings across all iterative pipelines
