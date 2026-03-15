# Documentation Audit Report
Generated: 2026-03-13 | Commit: e4738ec

## Executive Summary

| Metric | Count |
|--------|-------|
| Documents scanned | 12 (2 markdown, 9 dot files, 1 output.txt) |
| Claims verified | ~45 |
| Verified TRUE | ~29 (69%) |
| **Verified FALSE** | **8 (19%)** |
| Gaps identified | 8 |

The README.md is largely auto-generated Repomix boilerplate that does not accurately describe the project. It omits the most critical information (how to run these files with the `tracker` tool) and contains multiple stale/incorrect claims.

## False Claims Requiring Fixes

### README.md

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 11 | Clone URL: `https://github.com/harperreed/dot-files.git` | Org is `2389-research` (per tracker README). Should be `https://github.com/2389-research/dot-files.git` or similar | Update URL to correct org |
| 4 | "configuration scripts that cater to different use cases, such as debugging, documentation, and scenario testing" | Several files are games (20q.dot, story-engine.dot) or entertainment (model-debate.dot), not "configuration scripts" | Rewrite to accurately describe the mix of dev pipelines and interactive experiences |
| 20-21 | "Run a Dot File: You can execute the dot files according to the defined workflow" | Never mentions the `tracker` tool, which is the runtime engine for these files. Without tracker, these files are inert. | Add `tracker` as a prerequisite, show `tracker <file>.dot` as the run command |
| 29-34 | "File Exclusions... Log files, dependency lock files, environment files, binaries" | This is Repomix boilerplate. The repo has no log files, no dependency lock files, no environment files to exclude | Remove entire "File Exclusions" section or rewrite for this repo |
| 37-38 | "Each file content has been stripped of empty lines... Line numbers are added" | FALSE. The dot files contain empty lines and have no line numbers. This is copy-pasted Repomix metadata. | Remove this claim |
| 40 | "may contain sensitive information" | The repo is dot graph definitions. No secrets, no credentials. | Remove security warning or tone it down |
| 46-58 | Directory listing omits `output.txt` | `output.txt` exists in repo (untracked). Also missing: `docs/` directory if audits are committed | Either add to listing or add to `.gitignore` |

### DOT Files - Model References

All model references (`gpt-5-mini`, `gpt-5.4`, `gpt-5.2`, `gemini-3.5-flash`, `claude-opus-4-6`) have been **confirmed valid** by the project maintainer. No issues here.

### output.txt

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 70-72 | `README.md` content shown as `# dot-files` (single line) | Actual README.md is 68 lines with full content | output.txt is stale Repomix snapshot |

## Cross-Repository Analysis

### Tracker (../tracker)

The `tracker` repo (`/Users/harper/Public/src/2389/tracker`) is the **runtime engine** for these dot files. Key findings:

- **Tracker README line 27** references `[dotpowers](https://github.com/2389-research/dotpowers)` — this is a **separate repo** (`dotpowers/`) from `dot-files/`. The relationship between these two repos is unclear to a reader.
- The dot files in this repo extensively use `.tracker/` as a state directory (savepoints, counters, checkpoints), which is consistent with tracker's checkpoint mechanism (tracker README line 141).
- The dot files reference node shapes (`box`, `hexagon`, `parallelogram`, `component`, `tripleoctagon`) that all map to valid tracker handlers documented in the tracker README.
- The dot files use graph attributes (`goal`, `default_max_retry`, `retry_target`, `default_fidelity`, `model_stylesheet`) that are tracker-specific extensions to DOT syntax — none of this is documented in this repo's README.

### Mammoth (../mammoth-dev)

- The `mammoth-dev` repo exists at `/Users/harper/Public/src/2389/mammoth-dev`.
- The word "mammoth" appears in two ABOUTME comments:
  - `20q.dot:1` — "A 20 Questions game implemented as a mammoth DOT pipeline"
  - `story-engine.dot:1` — "An interactive fiction / choose-your-own-adventure game as a mammoth DOT pipeline"
- The README should link to mammoth's GitHub: `https://github.com/2389-research/mammoth-dev` (or equivalent).

## Gap Analysis (Pass 2B)

| Gap | Severity | Description |
|-----|----------|-------------|
| No tracker dependency documented | **Critical** | README never mentions `tracker` is required to run these files. Should link to [tracker GitHub](https://github.com/2389-research/tracker) |
| No mammoth link | **Critical** | README should link to [mammoth-dev GitHub](https://github.com/2389-research/mammoth-dev) to explain the DOT pipeline system |
| No per-file descriptions | High | No documentation of what each dot file does — just "review the contents" |
| No installation instructions | High | No `go install github.com/2389-research/tracker/cmd/tracker@latest` anywhere |
| No API key requirements | Medium | Running these pipelines requires Anthropic/OpenAI/Gemini API keys, not documented |
| No relationship to dotpowers explained | Medium | How does this repo relate to the `dotpowers` repo that tracker recommends? |
| No model compatibility matrix | Medium | Which models are required? Which are optional? What happens if a model is unavailable? |
| ABOUTME comments not on all files | Low | `output.txt` has no ABOUTME comment (per CLAUDE.md convention) |
| No CLAUDE.md in this repo | Low | Per user conventions, projects should have a CLAUDE.md |

## Pattern Summary

| Pattern | Count | Root Cause |
|---------|-------|------------|
| Repomix boilerplate in README | 4 claims | README was auto-generated by Repomix and never customized |
| Missing GitHub links | 2 repos | README should link to tracker and mammoth-dev GitHub repos |
| Missing runtime context | 3 gaps | No mention of tracker as the execution engine |
| Stale generated files | 1 | output.txt is a stale Repomix snapshot |

## Human Review Queue

- [ ] Verify whether the GitHub org for this repo is `harperreed` or `2389-research` and fix clone URL
- [ ] Add link to [tracker](https://github.com/2389-research/tracker) in README — it's the runtime engine
- [ ] Add link to [mammoth-dev](https://github.com/2389-research/mammoth-dev) in README — the DOT pipeline system
- [ ] Clarify relationship between `dot-files` and `dotpowers` repos
- [ ] Decide whether `output.txt` should be committed or gitignored
- [ ] Rewrite README to replace Repomix boilerplate with actual project documentation
