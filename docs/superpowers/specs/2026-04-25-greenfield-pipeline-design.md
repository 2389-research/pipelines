# Greenfield Reverse Engineering Pipeline — Design Spec

## Overview

A faithful port of [prime-radiant-inc/greenfield](https://github.com/prime-radiant-inc/greenfield) as a set of composable `.dip` pipelines for tracker. Greenfield reads source code, documentation, SDKs, runtime behavior, and binaries, then produces behavioral specifications, test vectors, acceptance criteria, and a full provenance trail. The output describes *what* the software does — not *how* any particular codebase does it.

**Goal:** Given a target path (source tree, bundle, binary, or installed software), produce sanitized behavioral specs, test vectors, and acceptance criteria in a `workspace/output/` directory that an implementation team can build against without inheriting the original's internal structure.

## Architecture

### Pipeline Composition

Five `.dip` files, composable and independently iterable:

```
greenfield.dip                  # Runner — chains subgraphs, state checks between layers
greenfield_discovery.dip        # L1: intelligence gathering
greenfield_synthesis.dip        # L2 + L3 + Gate 1/1b: synthesis → specs → verification
greenfield_validation.dip       # L4 + Gate 2 + L5: test vectors → review → sanitization
greenfield_review.dip           # L6 + L7: second-pass review + fidelity validation
```

The runner chains subgraphs sequentially with state-check tool nodes between each. Each subgraph can also be run independently for iteration/debugging.

### Model Assignments (Cross-Provider)

| Model | Provider | Roles | Rationale |
|---|---|---|---|
| gemini-3-flash-preview | Gemini | All L1 intelligence agents (8 agents) | High-volume reading, token-heavy, mechanically straightforward |
| claude-opus-4-6 | Anthropic | L2 synthesis, L3 deep specs, L5 sanitization, Gate 1/1b review, L6/L7 remediation | Judgment-heavy, core spec writing, deepest reasoning |
| gpt-5.4 | OpenAI | L4 test vectors, Gate 2 review, L6 reviewers (4 agents), L7 verdict | Structured output, cross-provider review catches blind spots |

### Quality Gate Pattern

All four gates (Gate 1, Gate 1b, Gate 2, L6/L7 reviews) follow the same two-stage pattern:

1. **Tool pre-check** — mechanical validation (files exist, provenance citations present, counts correct). Catches cheap issues without burning tokens.
2. **Agent review** — judgment calls (contradictions, quality, completeness, contamination). Uses `auto_status: true` with `max_retries: 3`. On failure, routes to a remediation agent. On retry exhaustion, routes to a terminal failure node via `fallback_target`.

```
ToolPreCheck → AgentReview (auto_status)
  → success → next layer
  → fail → Remediation agent → AgentReview (retry, max 3)
  → fallback → TerminalFailure → Exit
```

### Workspace Structure

Matches Greenfield's native layout exactly, so output is interchangeable with the Claude Code plugin:

```
workspace/
├── discovery-manifest.yaml       # L1 discovery output
├── workspace.json                # Metadata (target, timestamp, excluded sources)
├── raw/                          # RAW — requires sanitization before handoff
│   ├── source/                   # Source code analysis
│   │   ├── chunks/
│   │   ├── analysis/
│   │   ├── functions/
│   │   ├── manifests/
│   │   └── exploration/
│   ├── runtime/                  # Runtime observation
│   │   ├── cli/
│   │   ├── web/
│   │   ├── behaviors/
│   │   ├── ux-flows/
│   │   └── visual/
│   ├── binary/                   # Binary analysis
│   ├── project-history/          # Git archaeology output
│   ├── test-evidence/            # Test suite analysis output
│   ├── synthesis/                # L2 output
│   │   ├── features/
│   │   ├── architecture/
│   │   ├── api/
│   │   ├── behavioral-summaries/
│   │   └── module-map.md
│   └── specs/                    # L3/L4 output
│       ├── modules/
│       ├── journeys/
│       ├── contracts/
│       ├── test-vectors/
│       └── validation/
├── output/                       # Sanitized specs — implementation team reads this
│   ├── specs/                    # Per-domain behavioral specs
│   ├── test-vectors/             # Given/When/Then test vectors
│   └── validation/
│       └── acceptance-criteria/  # Formal acceptance criteria
├── provenance/                   # Citation audit trail
│   └── sessions/
└── review/                       # L6/L7 findings and remediation logs
```

---

## Pipeline 1: `greenfield.dip` — Runner

**Purpose:** Top-level orchestrator. Chains the four layer subgraphs with state checks between each.

**Workflow name:** `Greenfield`

**Node inventory (~12 nodes):**

| Node | Type | Model | Purpose |
|---|---|---|---|
| Start | agent | — | Acknowledge pipeline start |
| SetupWorkspace | tool | — | Create workspace directory structure, write workspace.json |
| DiscoverTarget | tool | — | Probe target path: file types, git presence, package manifests, binaries, docs. Write discovery-manifest.yaml |
| DiscoverTargetReview | agent | gemini-3-flash-preview | Only invoked if manifest has <2 non-community source types (community is always available via web search and doesn't count toward the threshold). Reviews target, augments manifest |
| L1_Discovery | subgraph | — | ref: greenfield_discovery.dip |
| CheckL1Output | tool | — | Verify workspace/raw/ has non-empty content from at least 1 source type |
| L2L3_Synthesis | subgraph | — | ref: greenfield_synthesis.dip |
| CheckSynthesisOutput | tool | — | Verify workspace/raw/specs/ and workspace/raw/synthesis/ exist with content |
| L4L5_Validation | subgraph | — | ref: greenfield_validation.dip |
| CheckValidationOutput | tool | — | Verify workspace/output/ has specs, test vectors, and acceptance criteria |
| L6L7_Review | subgraph | — | ref: greenfield_review.dip |
| FinalReport | agent | claude-opus-4-6 | Summarize: sources analyzed, spec count, test vector count, gate results, confidence |
| Exit | agent | — | Report completion |

**Edge flow:**

```
Start → SetupWorkspace → DiscoverTarget
DiscoverTarget → DiscoverTargetReview    when non_community_source_count < 2
DiscoverTarget → L1_Discovery            when non_community_source_count >= 2
DiscoverTargetReview → L1_Discovery
L1_Discovery → CheckL1Output            when ctx.outcome = success
L1_Discovery → DiscoveryFailed          when ctx.outcome = fail
CheckL1Output → L2L3_Synthesis          when ctx.tool_stdout = l1-ok
CheckL1Output → L1Failed                when ctx.tool_stdout != l1-ok
L2L3_Synthesis → CheckSynthesisOutput   when ctx.outcome = success
L2L3_Synthesis → SynthesisFailed        when ctx.outcome = fail
CheckSynthesisOutput → L4L5_Validation  when ctx.tool_stdout = synthesis-ok
CheckSynthesisOutput → SynthesisFailed  when ctx.tool_stdout != synthesis-ok
L4L5_Validation → CheckValidationOutput when ctx.outcome = success
L4L5_Validation → ValidationFailed      when ctx.outcome = fail
CheckValidationOutput → L6L7_Review     when ctx.tool_stdout = validation-ok
CheckValidationOutput → ValidationFailed when ctx.tool_stdout != validation-ok
L6L7_Review → FinalReport               when ctx.outcome = success
L6L7_Review → ReviewFailed              when ctx.outcome = fail
FinalReport → Exit
*Failed → Exit
```

**Setup tool details:**

`SetupWorkspace` creates the full directory tree and writes `workspace.json`:

```yaml
target: "<path from pipeline input>"
started_at: "<ISO timestamp>"
excluded_sources: []
pipeline_version: "1.0"
```

`DiscoverTarget` probes the target and writes `workspace/discovery-manifest.yaml`:

```yaml
target: "<path>"
sources:
  source_code: true/false
  docs: true/false
  sdk: true/false
  community: true  # always available (web search)
  runtime: true/false  # docker/podman detected
  binary: true/false  # decompiler detected
  git_history: true/false  # .git present
  tests: true/false  # test files detected
  visual: true/false  # UI detected
  contracts: true/false  # OpenAPI/protobuf/GraphQL detected
source_count: <N>
```

---

## Pipeline 2: `greenfield_discovery.dip` — L1 Intelligence Gathering

**Purpose:** Read the target through every available intelligence source. Write raw evidence to workspace/raw/.

**Workflow name:** `GreenfieldDiscovery`

**Node inventory (~20 nodes):**

| Node | Type | Model/Provider | Purpose |
|---|---|---|---|
| Start | agent | — | Acknowledge L1 start |
| ReadManifest | tool | — | Read discovery-manifest.yaml, emit source bitmask |
| WriteSkipMarkers | tool | — | For each unavailable source, write workspace/raw/<type>/.skipped |
| IntelligenceParallel | parallel | — | Fan-out to all 8 intelligence agents |
| SourceAnalyzer | agent | gemini-3-flash-preview / gemini | Read source code: chunk files, analyze functions, trace code paths. Write to workspace/raw/source/ |
| DocResearcher | agent | gemini-3-flash-preview / gemini | Read docs directories, READMEs, wikis. Write to workspace/public/docs/ |
| SdkAnalyzer | agent | gemini-3-flash-preview / gemini | Read package manifests, SDK dependencies, integration patterns. Write to workspace/public/ecosystem/ |
| CommunityAnalyst | agent | gemini-3-flash-preview / gemini | Web search for public docs, GitHub issues, discussions, blog posts. Write to workspace/public/community/ |
| RuntimeObserver | agent | gemini-3-flash-preview / gemini | Container-based runtime observation. Check docker/podman, run target, observe behavior. Write to workspace/raw/runtime/ |
| BinaryAnalyzer | agent | gemini-3-flash-preview / gemini | Decompile binaries, analyze symbols, trace execution. Write to workspace/raw/binary/ |
| GitArchaeologist | agent | gemini-3-flash-preview / gemini | Mine git log, blame, evolution patterns, deleted code. Write to workspace/raw/project-history/ |
| TestSuiteAnalyzer | agent | gemini-3-flash-preview / gemini | Read test files for behavioral evidence, run tests if possible. Write to workspace/raw/test-evidence/ |
| IntelligenceJoin | fan_in | — | Collect all 8 agents |
| CoverageCheck | tool | — | Count sources that produced non-skip output. Emit count |
| CoverageAgent | agent | claude-opus-4-6 / anthropic | Only if coverage < 2. Review what was found, suggest additional sources |
| WriteL1Summary | tool | — | Write workspace/raw/l1-summary.yaml with source counts and paths |
| Exit | agent | — | Report L1 completion |

**No-op pattern for parallel agents:**

Each L1 agent starts by checking for its skip marker:

```bash
if [ -f workspace/raw/<type>/.skipped ]; then
  echo "Source type <type> not available for this target" > workspace/raw/<type>/skipped-summary.md
  exit 0  # STATUS: success — graceful skip
fi
```

This avoids complex conditional edges for the 8-way fan-out. All 8 agents always run; unavailable ones no-op in seconds.

**Agent prompt pattern:**

Each L1 agent follows the same structure:
1. Check skip marker
2. Read target files relevant to its source type
3. Analyze exhaustively — every file, every function, every path
4. Write evidence to its designated workspace subdirectory
5. Every behavioral claim gets a `<!-- cite: source=<type>, ref=<path>, confidence=<level>, agent=<role> -->` provenance annotation
6. Write a summary manifest listing all evidence files produced

**SourceAnalyzer specifics:**

For large codebases, the SourceAnalyzer chunks files into manageable pieces:
- Reads the full source tree structure first
- Chunks files by module/directory (not by line count)
- Analyzes each chunk: functions, classes, methods, control flow, state
- Writes per-chunk analysis to workspace/raw/source/analysis/chunk-NNNN.md
- Writes function index to workspace/raw/source/functions/

**RuntimeObserver specifics:**

```bash
# Tool preamble checks for container runtime
if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
  echo "No container runtime available" > workspace/raw/runtime/.skipped
  exit 0
fi
```

The agent then:
1. Detects entry point (CLI, web server, library)
2. Builds/installs if needed
3. Runs the target in a container
4. Exercises CLI flags, API endpoints, interactive commands
5. Observes behavior, captures output
6. Documents behavioral findings with provenance

**BinaryAnalyzer specifics:**

Checks for `objdump`, `radare2`, or `ghidra` headless. Falls back to `strings` + `file` for minimal analysis. Documents symbol tables, string constants, linked libraries.

---

## Pipeline 3: `greenfield_synthesis.dip` — L2 Synthesis + L3 Deep Specs + Gate 1/1b

**Purpose:** Synthesize L1 evidence into a unified module map, then write deep behavioral specs. Gate 1 verifies correctness and completeness.

**Workflow name:** `GreenfieldSynthesis`

**Node inventory (~18 nodes):**

| Node | Type | Model/Provider | Purpose |
|---|---|---|---|
| Start | agent | — | Acknowledge L2/L3 start |
| ReadL1Summary | tool | — | Read l1-summary.yaml, verify L1 output exists |
| SynthesisParallel | parallel | — | Fan-out to L2 agents |
| FeatureDiscoverer | agent | claude-opus-4-6 / anthropic | Build feature inventory from all L1 evidence |
| ArchitectureAnalyst | agent | claude-opus-4-6 / anthropic | Infer architecture model, component boundaries, data flow |
| ApiExtractor | agent | claude-opus-4-6 / anthropic | Extract external API contracts: CLI flags, HTTP endpoints, env vars, config keys |
| ModuleMapper | agent | claude-opus-4-6 / anthropic | Map code structure to behavioral domains |
| SynthesisJoin | fan_in | — | Collect L2 outputs |
| Synthesizer | agent | claude-opus-4-6 / anthropic | Merge L2 outputs into unified module map (workspace/raw/synthesis/module-map.md) |
| DeepSpecsParallel | parallel | — | Fan-out to L3 agents |
| DeepDiveAnalyzer | agent | claude-opus-4-6 / anthropic | Write per-module behavioral specs |
| BehaviorDocumenter | agent | claude-opus-4-6 / anthropic | Write behavioral documentation with provenance |
| UserJourneyAnalyzer | agent | claude-opus-4-6 / anthropic | Map end-to-end user journeys |
| ContractExtractor | agent | claude-opus-4-6 / anthropic | Extract dependency contracts, protocol specs |
| DeepSpecsJoin | fan_in | — | Collect L3 outputs |
| Gate1ToolCheck | tool | — | Mechanical: files exist, provenance present, all modules covered, no empty specs |
| Gate1AgentReview | agent | claude-opus-4-6 / anthropic | Judgment: contradictions, assumed-claim ratio, spec quality. auto_status, max_retries: 3, retry_target: DeepDiveAnalyzer, fallback_target: Gate1Failed |
| Gate1bCompleteness | tool | — | Check every source file maps to at least one spec |
| Gate1bAgent | agent | claude-opus-4-6 / anthropic | Review completeness gaps. auto_status, max_retries: 2, retry_target: DeepDiveAnalyzer, fallback_target: Gate1Failed |
| WriteL2L3Summary | tool | — | Write synthesis/gate results summary |
| Gate1Failed | agent | — | Terminal failure report |
| Exit | agent | — | Report L2/L3 completion |

**Gate 1 tool pre-check (`Gate1ToolCheck`):**

```bash
errors=""
# Check raw spec files exist
spec_count=$(find workspace/raw/specs/modules/ -name "*.md" 2>/dev/null | wc -l)
if [ "$spec_count" -eq 0 ]; then errors="${errors}no-specs "; fi
# Check provenance citations
no_cite=$(grep -rL "<!-- cite:" workspace/raw/specs/modules/ 2>/dev/null | wc -l)
if [ "$no_cite" -gt 0 ]; then errors="${errors}missing-provenance-${no_cite}-files "; fi
# Check module map exists
if [ ! -f workspace/raw/synthesis/module-map.md ]; then errors="${errors}no-module-map "; fi
# Check journey specs
journey_count=$(find workspace/raw/specs/journeys/ -name "*.md" 2>/dev/null | wc -l)
if [ "$journey_count" -eq 0 ]; then errors="${errors}no-journeys "; fi
```

**Gate 1b completeness check (`Gate1bCompleteness`):**

Maps source files to spec references. For each source file in workspace/raw/source/, verifies at least one spec in workspace/raw/specs/ references it via provenance citation. Emits a gap list.

**Retry flow:**

Gate 1 failure → DeepDiveAnalyzer re-runs with gate findings as context → Gate 1 re-reviews. The gate findings are written to `workspace/raw/specs/gate1-findings.md` so the retry agent can read them. After 3 failures, `Gate1Failed` reports what passed and what didn't.

---

## Pipeline 4: `greenfield_validation.dip` — L4 Test Vectors + Gate 2 + L5 Sanitization

**Purpose:** Generate test vectors and acceptance criteria from the verified specs, review for implementation leakage, then sanitize everything into output-ready form.

**Workflow name:** `GreenfieldValidation`

**Node inventory (~14 nodes):**

| Node | Type | Model/Provider | Purpose |
|---|---|---|---|
| Start | agent | — | Acknowledge L4/L5 start |
| ReadSpecs | tool | — | Verify workspace/raw/specs/ exists, count modules |
| ValidationParallel | parallel | — | Fan-out to L4 agents |
| TestVectorGenerator | agent | gpt-5.4 / openai | Generate Given/When/Then test vectors for all P0 behavioral claims |
| TestGenerator | agent | gpt-5.4 / openai | Generate runnable test spec outlines |
| AcceptanceCriteriaWriter | agent | gpt-5.4 / openai | Write formal acceptance criteria per module with valid IDs |
| ValidationJoin | fan_in | — | Collect L4 outputs |
| Gate2ToolCheck | tool | — | Mechanical: all P0 behaviors have vectors, ACs have valid IDs, no impl leakage in artifacts |
| Gate2AgentReview | agent | gpt-5.4 / openai | Judgment: completeness, quality, leakage. auto_status, max_retries: 3, retry_target: TestVectorGenerator, fallback_target: Gate2Failed |
| SanitizationParallel | parallel | — | Fan-out to L5 sanitizers |
| SanitizerSpecs | agent | claude-opus-4-6 / anthropic | Rewrite raw specs to workspace/output/specs/ free of impl details |
| SanitizerTestVectors | agent | claude-opus-4-6 / anthropic | Sanitize test vectors to workspace/output/test-vectors/ |
| SanitizerAcceptanceCriteria | agent | claude-opus-4-6 / anthropic | Sanitize ACs to workspace/output/validation/acceptance-criteria/ |
| SanitizationJoin | fan_in | — | Collect L5 outputs |
| WriteL4L5Summary | tool | — | Write validation/sanitization summary |
| Gate2Failed | agent | — | Terminal failure report |
| Exit | agent | — | Report L4/L5 completion |

**Test vector format (Greenfield-native):**

```markdown
### TV-MODULE-001: Description
GIVEN: <precondition>
WHEN: <action>
THEN: <expected outcome>
```

**Acceptance criteria format:**

```markdown
### AC-MODULE-001: Description
GIVEN: <context>
WHEN: <trigger>
THEN: <observable result>
Linked specs: [spec-module-behavior-name]
```

**Sanitization rules (what the sanitizer agents follow):**

PRESERVE (behavioral interfaces):
- Environment variables, CLI flags, config keys
- API fields, wire protocol names
- User-facing paths, error messages
- Protocol names (SSE, gRPC, OAuth)

REMOVE (implementation details):
- Function names, variable names, minified identifiers
- Line numbers, source file paths
- Code structure ("calls X then Y")
- Internal data structure names

Provenance citations are preserved through sanitization — `<!-- cite: -->` annotations stay but source file paths become workspace-relative references.

**Gate 2 tool pre-check (`Gate2ToolCheck`):**

```bash
errors=""
# Check test vectors exist
tv_count=$(find workspace/raw/specs/test-vectors/ -name "*.md" 2>/dev/null | wc -l)
if [ "$tv_count" -eq 0 ]; then errors="${errors}no-test-vectors "; fi
# Check acceptance criteria exist
ac_count=$(find workspace/raw/specs/validation/ -name "*.md" 2>/dev/null | wc -l)
if [ "$ac_count" -eq 0 ]; then errors="${errors}no-acceptance-criteria "; fi
# Check for implementation leakage patterns in validation artifacts
leak_count=$(grep -rl "function \|def \|class \|import \|require(" workspace/raw/specs/test-vectors/ 2>/dev/null | wc -l)
if [ "$leak_count" -gt 0 ]; then errors="${errors}leakage-${leak_count}-files "; fi
```

---

## Pipeline 5: `greenfield_review.dip` — L6 Second-Pass Review + L7 Fidelity

**Purpose:** Independent review of sanitized output for contamination and fidelity loss. Also serves the `/sanitize` re-run use case.

**Workflow name:** `GreenfieldReview`

**Node inventory (~14 nodes):**

| Node | Type | Model/Provider | Purpose |
|---|---|---|---|
| Start | agent | — | Acknowledge L6/L7 start |
| ReadSanitizedOutput | tool | — | Verify workspace/output/ has content |
| ReviewParallel | parallel | — | Fan-out to L6 reviewers |
| StructuralLeakageReviewer | agent | gpt-5.4 / openai | Look for code structure bleeding through (module boundaries matching source tree, internal naming patterns) |
| ContentContaminationReviewer | agent | gpt-5.4 / openai | Look for variable names, file paths, identifiers, minified symbols |
| BehavioralCompletenessReviewer | agent | gpt-5.4 / openai | Check nothing was lost — compare output/ spec count and coverage against raw/ |
| DeepReadAuditor | agent | gpt-5.4 / openai | Line-by-line audit of output specs for any contamination the other reviewers missed |
| ReviewJoin | fan_in | — | Collect L6 findings |
| L6ToolCheck | tool | — | Count findings, check severity levels |
| L6AgentVerdict | agent | gpt-5.4 / openai | Render pass/fail. auto_status, max_retries: 3, retry_target: RemediateL6, fallback_target: L6Failed |
| RemediateL6 | agent | claude-opus-4-6 / anthropic | Fix contamination flagged by reviewers, rewrite affected output specs |
| FidelityParallel | parallel | — | Fan-out to L7 validators |
| FidelityValidatorSpecs | agent | claude-opus-4-6 / anthropic | Compare raw/ vs output/ specs, flag lost behavioral detail |
| FidelityValidatorTestVectors | agent | claude-opus-4-6 / anthropic | Compare raw/ vs output/ test vectors, flag weakened assertions |
| FidelityJoin | fan_in | — | Collect L7 findings |
| L7ToolCheck | tool | — | Count fidelity flags |
| L7AgentVerdict | agent | gpt-5.4 / openai | Render pass/fail. auto_status, max_retries: 3, retry_target: RemediateL7, fallback_target: L7Failed |
| RemediateL7 | agent | claude-opus-4-6 / anthropic | Restore behavioral detail that was over-sanitized |
| WriteReviewSummary | tool | — | Write review/fidelity results summary |
| L6Failed | agent | — | Terminal L6 failure report |
| L7Failed | agent | — | Terminal L7 failure report |
| Exit | agent | — | Report L6/L7 completion |

**L6 review methodology:**

Each L6 reviewer writes findings to `workspace/review/l6-<reviewer-name>.md`:

```markdown
## Finding F-001
**Severity:** high | medium | low
**Location:** workspace/output/specs/<file>
**Issue:** <description of contamination>
**Evidence:** <the offending text>
**Recommendation:** <how to fix>
```

`L6ToolCheck` counts findings by severity. If any high-severity findings exist, it emits `l6-has-findings`. If only low/medium, it still emits findings but the agent verdict may pass with notes.

**L7 fidelity methodology:**

Each L7 validator compares raw/ and output/ side by side:

```markdown
## Fidelity Flag FL-001
**Raw spec:** workspace/raw/specs/modules/<file>
**Output spec:** workspace/output/specs/<file>
**Lost detail:** <behavioral detail present in raw but weakened or absent in output>
**Severity:** critical | notable | minor
**Recommendation:** <how to restore without reintroducing contamination>
```

**Remediation agents:**

`RemediateL6` reads L6 findings, rewrites the affected files in workspace/output/. It re-sanitizes only the flagged sections, preserving the rest.

`RemediateL7` reads L7 fidelity flags, restores lost behavioral detail while being careful not to reintroduce implementation contamination. This is the hardest job in the pipeline — balancing fidelity against cleanliness.

---

## Provenance Methodology

Every behavioral claim throughout the pipeline carries a provenance citation:

```markdown
Sessions expire after 30 minutes of inactivity.
<!-- cite: source=source-code, ref=workspace/raw/source/analysis/chunk-0046.md:23, confidence=confirmed, agent=deep-dive-analyzer, corroborated_by=runtime-observation -->
```

**Confidence levels:**
- `confirmed` — 2+ independent sources agree
- `inferred` — single source, direct evidence
- `assumed` — reasoning from indirect evidence

Citations survive through sanitization. Source file paths in citations become workspace-relative references (not references to the original target's file paths).

---

## Node Count Summary

| File | Estimated Nodes | Layers |
|---|---|---|
| greenfield.dip | ~12 | Runner |
| greenfield_discovery.dip | ~20 | L1 |
| greenfield_synthesis.dip | ~18 | L2 + L3 + Gate 1/1b |
| greenfield_validation.dip | ~14 | L4 + Gate 2 + L5 |
| greenfield_review.dip | ~16 | L6 + L7 |
| **Total** | **~80** | |

---

## Edge Cases and Failure Modes

### Target has no source code (binary only)
- DiscoverTarget detects binary but no source
- L1 runs BinaryAnalyzer and RuntimeObserver (if container available), skips SourceAnalyzer
- L2/L3 work from binary analysis + runtime evidence
- Confidence levels will be lower (more `inferred`, fewer `confirmed`)

### Target has only source code (no docs, no tests)
- DiscoverTarget finds source only
- L1 runs SourceAnalyzer, skips others (except CommunityAnalyst which always runs via web search)
- CoverageCheck triggers CoverageAgent (< 2 non-community sources)
- CoverageAgent may identify docs embedded in source (inline comments, docstrings) and augment manifest

### Gate failure after max retries
- Each gate has a terminal failure node that reports what passed and what didn't
- The runner's Check*Output nodes detect the failed subgraph and route to a failure exit
- Partial results remain in workspace/ for manual inspection

### Large codebase (10k+ files)
- SourceAnalyzer chunks by module/directory, not by file count
- Each chunk gets its own analysis file
- The chunking strategy is part of the SourceAnalyzer prompt, not a DIP structural concern

### No container runtime available
- RuntimeObserver writes skip marker and exits cleanly
- Pipeline continues with source + docs + other available sources
- Specs note that runtime behavior was not directly observed

---

## What the Output Looks Like

After a successful run, `workspace/output/` contains:

### `output/specs/`
Per-domain behavioral specifications. Each file describes what the software does in that behavioral domain. No source file references, no function names, no internal structure. Every claim has a provenance citation.

### `output/test-vectors/`
Concrete Given/When/Then test vectors organized by domain. An implementation team can use these directly to drive TDD.

### `output/validation/acceptance-criteria/`
Formal acceptance criteria with unique IDs, linked to specific spec claims. These define "done" for each behavioral requirement.

### `provenance/sessions/`
Audit trail. Which agents ran, what they read, what they concluded. Allows tracing any output claim back to its evidence source.
