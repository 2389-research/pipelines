# YAML Pipeline Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the behavioral bugs in the YAML sprint pipelines around completion detection, stack propagation, durable attempt history, resume gating, and decomposition verification.

**Architecture:** Keep the existing YAML pipeline structure intact and apply surgical fixes in the four active YAML `.dip` files. Add a top-level completion check in `spec_to_ship_yaml.dip`, move `yq` gating earlier in `spec_to_sprints_yaml.dip`, enrich sprint YAML schema so `write_ledger` can populate `project.stack`, and record durable success/failure state in `sprint_exec_yaml.dip`.

**Tech Stack:** Dippin `.dip` DSL, `tracker`, `dippin`, POSIX shell, `yq`

---

### Task 1: Gate End-to-End Completion Correctly

**Files:**
- Modify: `spec_to_ship_yaml.dip`

- [ ] Add a verification tool after `run_sprints` to distinguish fully completed execution from a user pause.
- [ ] Route only the true completion path into the final ship summary.
- [ ] Add a paused/incomplete summary path so partial runs are not misreported as shipped.

### Task 2: Force Resume Paths Through yq Readiness

**Files:**
- Modify: `spec_to_sprints_yaml.dip`

- [ ] Move the `yq`/workspace gate ahead of `check_resume`.
- [ ] Keep the existing install-and-retry behavior intact for missing `yq`.
- [ ] Ensure resumed decomposition paths cannot jump straight into `yq`-dependent nodes.

### Task 3: Populate Structured Stack Metadata

**Files:**
- Modify: `spec_to_sprints_yaml.dip`

- [ ] Expand the sprint YAML schema in the writer prompt to include explicit stack fields.
- [ ] Require bootstrap sprint output to carry the project stack extracted from spec analysis.
- [ ] Tighten output validation so stack metadata is expected and can be propagated into the ledger.

### Task 4: Persist Durable Attempt and Failure History

**Files:**
- Modify: `sprint_exec_yaml.dip`

- [ ] Increment attempt counters durably when a sprint run starts.
- [ ] Append success and failure records to sprint YAML history.
- [ ] Mark terminal failure state in the ledger and sprint YAML before exiting failure paths.

### Task 5: Strengthen Wrapper Decomposition Verification

**Files:**
- Modify: `spec_to_ship_yaml.dip`

- [ ] Verify that `ledger.yaml`, `SPRINT-*.yaml`, and `SPRINT-*.md` are mutually consistent before execution begins.
- [ ] Fail early with a decomposition error if the wrapper sees partial or inconsistent output.

### Task 6: Validate

**Files:**
- Modify: `spec_to_sprints_yaml.dip`
- Modify: `sprint_exec_yaml.dip`
- Modify: `spec_to_ship_yaml.dip`
- Reference: `sprint_runner_yaml.dip`

- [ ] Re-run the red-phase shell assertions and confirm they now pass.
- [ ] Run `dippin validate` on the four YAML pipelines.
- [ ] Run `tracker validate` on the four YAML pipelines.
