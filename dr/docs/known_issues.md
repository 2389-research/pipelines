# Known Issues — dr/ Pipelines

Issues identified during real-world runs that should be fixed but are deferred (we are heads-down on getting clients to ship, not on pipeline iteration).

---

## ISSUE-001 — Sprint plan can contain dependency cycles

**Severity:** High (causes `deps_blocked_exit` mid-run, blocks downstream sprints permanently)
**Discovered:** 2026-05-12 on `nifb-dr` workspace (run `b647506fb027`)
**Pipeline:** `spec_to_sprints.dip` (sprint generation), surfaced by `sprint_exec.dip:FindNextSprint`

### Symptom

After several sprints complete, `FindNextSprint` returns `deps-blocked` even though
multiple sprints remain in status `planned`. Inspection shows the remaining planned
sprints form a circular dependency:

```
nifb-dr observed state (8 planned sprints, deps_blocked):

020 ← 017, 018, 030            # 030 is planned (back-edge)
021 ← 014, 025, 027            # 025, 027 planned (back-edges)
022 ← ..., 020, 021, 025, 027, 030
023 ← ..., 020, 021, 022, 025, 027, 030
025 ← 000-024 (planned-blockers: 020, 021, 022, 023)
027 ← 000-026 (planned-blockers: 020, 021, 022, 023, 025)
030 ← 000-029 (planned-blockers: 020, 021, 022, 023, 025, 027)
032 ← 000-031 (planned-blockers: 020, 021, 022, 023, 025, 027, 030)
```

Sprint 020 has lower ID than 030 but depends on 030 — the convention is that lower-numbered
sprints come first, so a lower-ID sprint depending on a higher-ID sprint is a back-edge.
Multiple back-edges across 020/021/022/023 close the cycle.

### Root cause (suspected — needs verification)

Three candidates, all observed:

1. **Decomposition agent prompt does not enforce topological ordering.** The agent
   writing `.ai/sprint_plan.md` and the sprint YAMLs is not explicitly told that
   `depends_on` must reference only sprints with strictly lower IDs. The LLM picks
   semantically-correct deps (e.g., "the UI sprint depends on the API sprint") without
   regard to numbering, then numbers them in whatever order it generates them.
   **Confirmed:** the initial nifb-dr plan included 020 ← 030, with both created
   simultaneously at decomposition time.

2. **`validate_output` capstone auto-fix may over-extend deps.** The capstone check
   (in `dr/parts/decomposition/write_and_validate_sprint_artifacts.dip:validate_output`)
   forces the last sprint to `depends_on` every other sprint. If redecomposition
   appends new sprints, the previous capstone's deps were already broad. Needs
   traceback. (Not yet confirmed.)

3. **Redecompose splice creates new back-edges on every run.** Each time a sprint
   gets redecomposed into children, the splice path appears to update sibling sprints
   to depend on the new children — even if those siblings predate the children. After
   021 was redecomposed into 033/034/035 on nifb-dr, sprints 022 and 023 (which
   already existed and were ahead of 021's children) suddenly had `035` in their
   `depends_on` lists. This is the most damaging variant: it means every successful
   redecompose can trigger a fresh `deps_blocked_exit` on the next iteration. **Confirmed
   twice** on nifb-dr run `81e1bde425d1`. The splice logic in `sprint_runner.dip` and
   `redecompose_sprint` paths needs to be audited — likely in `splice_ledger` or in
   the redecompose agent's prompt itself (it may be told to "add the new sprint as a
   dependency of everything that semantically needs it" without bounding by ID).

### Workaround (when encountered mid-run)

```sh
# 1. Identify the back-edges. For each planned sprint, list deps that are also planned:
yq '.sprints[] | select(.status == "planned") | .id + " <- " + (.depends_on | join(","))' .ai/ledger.yaml

# 2. For each planned sprint with lower ID, edit BOTH ledger.yaml AND the per-sprint YAML
#    to drop deps that point to higher-numbered planned sprints.
#    (Lower-numbered planned sprints should be the ones that run first to break the cycle.)
yq -i '(.sprints[] | select(.id == "020")).depends_on = ["017", "018"]' .ai/ledger.yaml
yq -i '.depends_on = ["017", "018"]' .ai/sprints/SPRINT-020.yaml
# ...repeat for 021/022/023 or similar early-but-blocked sprints

# 3. git add + commit the workspace edits

# 4. Re-run sprint_runner.dip — it picks up the now-unblocked sprint
```

### Fix candidates (when we get back to the pipeline)

1. **Add a DAG-validation check to `validate_output`** in the decomposition cluster:
   for each sprint, assert `all(d < id for d in depends_on)`. If false, emit token
   `back-edge-<sprint-id>-<bad-dep>` and let `RewriteOutput` fix it (taxonomy entry
   needed: "drop deps with id >= self.id"). **✓ Shipped** in `dr/parts/decomposition/write_and_validate_sprint_artifacts.dip:validate_output` (back-edge loop emits `back-edge-<self>-<bad-dep>` tokens). Recipe in `dr/docs/validation_error_taxonomy.md:7.`
2. **Add an explicit constraint to the decomposition agent prompt:** "depends_on
   MUST only reference sprints with strictly lower IDs. If sprint A needs work from
   sprint B, then A's ID must be greater than B's ID — renumber if necessary."
   **✓ Shipped** in `dr/spec_to_sprints.dip:write_sprint_docs` (Rules block now mandates strict topological ID ordering AND "test sprints come last"). DecompositionManager also now checks for back-edges as a hard-fail.
3. **Audit the capstone auto-fix** for ordering invariants — it currently only
   rewrites the LAST sprint's deps but may need to also strip back-edges from earlier
   sprints when redecomposition reorders things. **✓ Shipped** in `dr/parts/decomposition/write_and_validate_sprint_artifacts.dip:validate_output` — capstone auto-fix now only adds deps with strictly lower IDs than the capstone, so a redecomp-appended sprint can't be made to depend on lower-ID test sprints.
4. **Bound the redecompose splice's `dependents_to_rewrite` so it never creates back-edges.** **✓ Shipped** in `dr/spec_to_sprints.dip:redecompose_single` prompt — agent now must omit dependents whose IDs are LOWER than the new last-child, and emit a `dependents_omitted` block instead.

### Remaining work

- **Stale `.ai/redecompose-request.yaml` replay after tracker restart.** Not yet
  hardened. Workaround: clear it manually before relaunching tracker. Fix
  candidates: timestamp/run-id-stamp the request file and reject stale ones; or
  clear it in `report_progress` if its `failed_sprint_id` already has a non-failed status.
- **Regression test fixture.** `nifb-dr` workspace at commit immediately before
  the manual dep-cycle fix has a captured cycle — should be lifted into a fixture
  at `dr/tests/fixtures/dep-cycle-from-decomposition/` so `validate_output` is
  regression-tested against it.
