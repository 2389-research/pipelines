# Handoff: Sprint Pipeline Hardening (2026-04-27)

## State: READY TO RUN

All changes complete. Doctor Biz kicks off the pipeline next.

## What Was Done

### 1. Safety Gates (sprint_exec_yaml_v2.dip)
4 new tool nodes: PreflightComplexity, CheckScopeFence, CrossValidation, PreCommitAudit.
- CheckScopeFence uses md5sum snapshot comparison (not git diff HEAD) for ledger
- CheckLedgerIntegrity no longer deletes snapshot (downstream gates need it)
- CheckScopeFence failure routes to SnapshotLedger for clean retry
- PreCommitAudit uses snapshot restoration, cleans up snapshot at end

### 2. Models (sprint_exec_yaml_v2.dip)
- claude-opus-4-6 → claude-opus-4-7, ImplementSprint → gpt-5.5, all gpt-5.4 → gpt-5.5

### 3. Failed Sprints Reset (code-agent ledger + sprint YAMLs)
9 sprints to planned: 010, 012, 016, 021, 022, 030, 031, 032, 033

### 4. Runner Budget (sprint_runner_yaml_v2.dip)
Lines 171+178: ge 3 → ge 10

## Files Modified
- pipelines/sprint_exec_yaml_v2.dip — gates, models, edges
- pipelines/sprint_runner_yaml_v2.dip — budget 3→10
- code-agent/.ai/ledger.yaml — 9 sprints reset
- code-agent/.ai/sprints/SPRINT-{010,012,016,021,022,030,031,032,033}.yaml — reset

## Watch Items
1. Sprint 025a recurring ledger scope-fence violation — new gates should catch
2. Stale redecompose-request.yaml from Sprint 015 may need cleanup
3. Greenfield spec has uncommitted changes (unrelated)
