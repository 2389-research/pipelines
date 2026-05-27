# Track B Phase 1: `tool_access: none` on acknowledge-only agents

**Goal:** Convert pure-acknowledge agent Start/Exit nodes from prompt-level "HARD CONSTRAINT" tool-access copy to dippin-lang v0.32.0's `tool_access: none` structural primitive. Closes the prompt-vs-language gap for the v0.28.2 single-agent multi-tool-call vector.

**Scope:** Category A sites only — 22 sites across 12 files in `greenfield/` and `sprint/`. Mechanical conversion: drop tool-access clauses, add `tool_access: none`, preserve policy clauses. (Original plan listed ~26 sites; 2 were reclassified to Category C during execution — see `sprint_runner_yaml*.dip:130` rows below.)

**Tech:** dippin-lang v0.32.0 (new `tool_access` field; `DIP139` lint), tracker v0.31.0 (vendors v0.32.0). Local toolchain already bumped.

**Deferred** (tracked separately):
- [#18](https://github.com/2389-research/pipelines/issues/18) — Phase 2: Category B status-emitter agents (~10 sites, needs per-site STATUS-emission verification)
- [#19](https://github.com/2389-research/pipelines/issues/19) — Runtime smoke tests (real backend invocations to catch implicit-tool dependencies static checks miss)
- [#20](https://github.com/2389-research/pipelines/issues/20) — CHANGELOG entry + migration note + agent-node-safety.md update

---

## Semantic distinction: tool-access vs policy

"HARD CONSTRAINT" lines in this codebase carry two distinct payloads, often in the same sentence:

1. **Tool-access bound** — "Do NOT read project files / write code / modify files." `tool_access: none` replaces this structurally.
2. **Policy bound** — "Do NOT fabricate evidence / Your ONLY job is to X / If you finish early, stop and report." `tool_access: none` does NOT replace this; it's about response behavior, not tool registry.

The conversion rule below isolates these. Dropping policy clauses silently is the most likely way to regress a converted agent.

---

## Conversion rule

For each Category A site:

1. **Add `tool_access: none`** after `max_turns:` (or wherever fits the file's field-ordering convention).
2. **Split the HARD CONSTRAINT line into tool-access clauses and policy clauses.**
3. **Drop tool-access clauses** — "Do NOT read/write/modify/create/delete files", "Do NOT run tests/install deps", "Do NOT read project files".
4. **Preserve policy clauses** — "Your ONLY job is to acknowledge X", "If you finish early, stop", "Do NOT fabricate evidence". Rewrite as plain instructions (drop the "HARD CONSTRAINT:" prefix).
5. If the whole line is tool-access clauses, delete the line entirely (and any trailing blank line so the block ends cleanly).
6. **Skip + reclassify** if the agent has an explicit `tools: [...]` block (DIP139 will error on the coexistence).
7. **Skip + reclassify** if a later prompt line references "per HARD CONSTRAINT above" (semantic dependency — manual review).
8. **Do not modify** any node not on the Category A list, even if it has a HARD CONSTRAINT line.

---

## Site classification

### Category A — convert in this PR

| File | Site lines | Agent |
|---|---|---|
| `greenfield/greenfield.dip` | 17, 24 | Start, Exit |
| `greenfield/greenfield_discovery.dip` | 22, 30 | Start, Exit |
| `greenfield/greenfield_review.dip` | 21, 28 | Start, Exit |
| `greenfield/greenfield_synthesis.dip` | 21, 28 | Start, Exit |
| `greenfield/greenfield_validation.dip` | 21, 28 | Start, Exit |
| `sprint/sprint_exec-cheap.dip` | 14, 21 | Start, Exit |
| `sprint/sprint_exec_yaml.dip` | 17, 24 | Start, Exit |
| `sprint/sprint_exec_yaml_v2.dip` | 17, 24 | Start, Exit |
| `sprint/sprint_runner_yaml.dip` | 19, 27 | Start, Exit (line :130 reclassified to C during execution — its prompt says "Read .ai/ledger.yaml") |
| `sprint/sprint_runner_yaml_v2.dip` | 19, 27 | Start, Exit (same reclassification as above) |
| `sprint/verify_sprint.dip` | 35 | (single acknowledge-completion) |
| `sprint/verify_sprints_runner.dip` | 26 | (single acknowledge-completion) |

Line numbers will shift as edits land — always regenerate via grep before relying on them.

### Other categories — explicitly NOT converted in this PR

- **B (status emitters)** — see [#18](https://github.com/2389-research/pipelines/issues/18)
- **C (read-bounded)** — agents that legitimately read files (e.g. "identify the next sprint" reads the ledger). HARD CONSTRAINT bounds *writes*; keep as-is.
- **D (write-bounded implementers)** — agents that write by design ("implement ONLY the current sprint"). HARD CONSTRAINT bounds *scope*; keep as-is.

C and D sites in scope grep but stay untouched. The "expected HARD CONSTRAINT remaining" count after this PR is the C+D count (~27 sites).

---

## Execution

### Step 1: Branch + regenerate authoritative site list

```bash
git checkout main && git pull
git checkout -b track-b-cat-a

# Authoritative list of every HARD CONSTRAINT site in the repo. The `tools: none`
# / `tools:none` idioms were speculative in earlier drafts; this codebase only
# ever used "HARD CONSTRAINT" copy as the prompt-level pseudo-bound, so the grep
# narrows to that one phrase.
grep -rn "HARD CONSTRAINT" --include="*.dip" . | sort > /tmp/track-b-sites.txt
wc -l /tmp/track-b-sites.txt
```

Expected ~41 lines pre-conversion (matches the sum of Category A+B+C+D rows in the inventory). Cross-reference with the Category A table above — anything the table claims that grep doesn't find (or vice versa) is a drift bug; fix the table before continuing.

### Step 2: Sanity-check no candidate has an explicit `tools:` block

```bash
grep -l "^[[:space:]]*tools:" greenfield/*.dip sprint/*.dip 2>&1
```

Expected: no matches. If any candidate file has both `tools: [...]` and would gain `tool_access: none`, DIP139 will error — reclassify that site before converting.

### Step 3: Convert per file, one commit each

For each file in the Category A table:

1. Read the file's HARD CONSTRAINT context: `grep -n -B3 -A4 "HARD CONSTRAINT" <file>`
2. For each Category A site, apply the conversion rule above (Edit tool, per agent node).
3. `dippin doctor <file>` — confirm zero new errors and no new DIP IDs vs. the prior state.
4. `git commit -m "fix(<bucket>): tool_access: none on Category A agents in <file>"`

Per-file commits make rollback surgical if something turns out wrong.

### Step 4: Verify

```bash
# Lint sweep on every changed file.
for f in $(git diff --name-only main); do dippin doctor "$f" 2>&1 | grep -E "Grade:|Warnings:"; done

# Parse one converted file through tracker to confirm the field is understood.
tracker validate sprint/sprint_runner_yaml_v2.dip
```

If `dippin doctor` introduces new errors or `tracker validate` rejects the file, halt. The vendored dippin in tracker v0.31.0 is a pre-release SHA; if it doesn't recognize `tool_access`, the sweep can't ship until tracker catches up.

### Step 5: Bump README minimum-tracker pin

Update README's "Requirements" section to require tracker ≥ v0.31.0 (was ≥ v0.30.0). Without this bump, downstream users on v0.30.0 will silently parse the workflows but fall back to prompt-only safety — the structural change wouldn't apply.

### Step 6: PR

```bash
git push -u origin track-b-cat-a
gh pr create --title "fix(pipelines): tool_access: none on acknowledge-only agents" --body "..."
```

PR body must include:
- Why now: dippin-lang#41 closed in v0.32.0; tracker v0.31.0 vendors it
- Scope: Category A only (22 sites, 12 files — see header for the reclassification note)
- README pin bumped from tracker ≥ v0.30.0 → ≥ v0.31.0
- Follow-ups: #18 (Phase 2), #19 (smoke tests), #20 (broader docs)
- Note any HARD CONSTRAINT policy clauses preserved as plain instructions (i.e. sites where the line wasn't 100% tool-access — these are the easiest to mis-handle, so list them explicitly for reviewer attention)

---

## Rollback

If something breaks: `git revert <merge-sha>`. Per-file commits within the branch make selective revert possible if only some files regress, but the default response to a runtime regression is "revert the PR; reopen with a smaller scope."

If a converted agent breaks mid-pipeline at runtime: also `rm -rf .ai/` on affected workspaces to clear any half-finalized state before re-running.
