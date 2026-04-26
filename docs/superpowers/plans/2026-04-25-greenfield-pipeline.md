# Greenfield Reverse Engineering Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the Greenfield 7-layer reverse engineering pipeline as 5 composable .dip files for tracker.

**Architecture:** Five composable pipelines (runner + 4 layer subgraphs) with cross-provider model assignments (Gemini for L1, Opus for L2/L3/L5, GPT-5.4 for L4/L6/L7), quality gates with tool pre-checks and agent reviews, and workspace-level retry sentinels.

**Tech Stack:** DIP pipeline language, tracker CLI, yq, bash

**Spec:** `docs/superpowers/specs/2026-04-25-greenfield-pipeline-design.md`

**Files to create:**
- `greenfield_discovery.dip` — L1 intelligence gathering (~20 nodes)
- `greenfield_synthesis.dip` — L2 + L3 + Gate 1/1b (~20 nodes)
- `greenfield_validation.dip` — L4 + Gate 2 + L5 (~16 nodes)
- `greenfield_review.dip` — L6 + L7 (~16 nodes)
- `greenfield.dip` — Runner (~14 nodes)

**DIP format reference:** Study `sprint_exec_yaml_v2.dip` and `sprint_runner_yaml_v2.dip` for syntax patterns.

---

### Task 1: Create greenfield_discovery.dip — skeleton + tool nodes

**Files:**
- Create: `greenfield_discovery.dip`

- [ ] **Step 1: Create the file with workflow header, defaults, Start/Exit, and all tool nodes**

```
# ABOUTME: L1 intelligence gathering pipeline for Greenfield reverse engineering.
# ABOUTME: Reads target through 8 parallel intelligence sources, writes raw evidence to workspace/raw/.
workflow GreenfieldDiscovery
  goal: "Read the target through every available intelligence source (source code, docs, SDK, community, runtime, binary, git history, tests). Write raw evidence to workspace/raw/ with provenance citations. Each agent writes a completion marker (.completed, .skipped, or .failed) for fan-in verification."
  start: Start
  exit: Exit

  defaults
    max_restarts: 10
    fidelity: summary:medium

  agent Start
    label: Start
    max_turns: 1
    prompt:
      Acknowledge that the L1 intelligence gathering pipeline is starting. Report ready status.

      HARD CONSTRAINT: Do NOT read project files. Do NOT write code. Do NOT create, modify, or delete any files. Your ONLY job is to acknowledge the pipeline start.

  agent Exit
    label: Exit
    max_turns: 1
    prompt:
      L1 intelligence gathering complete. Report final status.

      HARD CONSTRAINT: Do NOT write code. Do NOT create, modify, or delete any files. Your ONLY job is to acknowledge completion.

  tool ReadManifest
    label: "Read Discovery Manifest"
    timeout: 10s
    command:
      set -eu
      if [ ! -f "workspace/discovery-manifest.yaml" ]; then
        printf 'no-manifest'
        exit 0
      fi
      count=$(yq '.source_count' "workspace/discovery-manifest.yaml")
      printf 'manifest-ready-%s-sources' "$count"

  tool WriteSkipMarkers
    label: "Write Skip Markers"
    timeout: 15s
    command:
      set -eu
      sources="source_code:source docs:public/docs sdk:public/ecosystem community:public/community runtime:runtime binary:binary git_history:project-history tests:test-evidence"
      for entry in $sources; do
        key=$(printf '%s' "$entry" | cut -d: -f1)
        dir=$(printf '%s' "$entry" | cut -d: -f2)
        available=$(yq ".sources.${key}" "workspace/discovery-manifest.yaml" 2>/dev/null)
        if [ "$key" = "community" ]; then
          continue
        fi
        case "$dir" in
          public/*) base="workspace/$dir" ;;
          *) base="workspace/raw/$dir" ;;
        esac
        mkdir -p "$base"
        if [ "$available" != "true" ]; then
          printf 'Source type %s not available for this target\n' "$key" > "$base/.skipped"
        fi
      done
      mkdir -p "workspace/public/community"
      printf 'skip-markers-written'

  tool CoverageCheck
    label: "Coverage Check"
    timeout: 15s
    command:
      set -eu
      completed=0
      skipped=0
      failed=0
      missing=0
      dirs="workspace/raw/source workspace/public/docs workspace/public/ecosystem workspace/public/community workspace/raw/runtime workspace/raw/binary workspace/raw/project-history workspace/raw/test-evidence"
      for d in $dirs; do
        if [ -f "$d/.completed" ]; then
          completed=$((completed + 1))
        elif [ -f "$d/.skipped" ]; then
          skipped=$((skipped + 1))
        elif [ -f "$d/.failed" ]; then
          failed=$((failed + 1))
        else
          missing=$((missing + 1))
        fi
      done
      if [ "$missing" -gt 0 ]; then
        printf 'incomplete-missing-%s-markers' "$missing"
        exit 0
      fi
      non_community=$((completed - 1))
      if [ "$completed" -le 1 ]; then
        non_community=0
      fi
      printf 'coverage-%s-completed-%s-skipped-%s-failed-noncommunity-%s' "$completed" "$skipped" "$failed" "$non_community"

  tool WriteL1Summary
    label: "Write L1 Summary"
    timeout: 10s
    command:
      set -eu
      completed=0
      dirs="workspace/raw/source workspace/public/docs workspace/public/ecosystem workspace/public/community workspace/raw/runtime workspace/raw/binary workspace/raw/project-history workspace/raw/test-evidence"
      for d in $dirs; do
        if [ -f "$d/.completed" ]; then
          completed=$((completed + 1))
        fi
      done
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      printf 'completed_sources: %s\ntimestamp: "%s"\nprovider_fallback: false\n' "$completed" "$now" > "workspace/raw/l1-summary.yaml"
      printf 'l1-summary-written-%s-sources' "$completed"
```

- [ ] **Step 2: Add placeholder edges (will be expanded in Task 2)**

```
  edges
    Start -> ReadManifest
    ReadManifest -> WriteSkipMarkers  when ctx.tool_stdout startswith manifest-ready  label: manifest_ok
    ReadManifest -> Exit              when ctx.tool_stdout = no-manifest              label: no_manifest
    ReadManifest -> Exit
    WriteSkipMarkers -> Exit
```

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield_discovery.dip 2>&1 | tail -3`
Expected: `valid` with a small number of nodes (~6) and edges.

- [ ] **Step 4: Commit**

```bash
git add greenfield_discovery.dip
git commit -m "feat(greenfield): create discovery pipeline skeleton with tool nodes"
```

---

### Task 2: Add L1 intelligence agents to greenfield_discovery.dip

**Files:**
- Modify: `greenfield_discovery.dip`

- [ ] **Step 1: Add IntelligenceParallel, all 8 agents, and IntelligenceJoin**

Add after the `WriteSkipMarkers` tool and before the `CoverageCheck` tool. Each agent uses `gemini-3-flash-preview / gemini` with `reasoning_effort: high`.

Each L1 agent prompt follows this pattern:
1. Check for `.skipped` marker — if present, write a skip summary and report STATUS: success
2. Read the target files relevant to its source type exhaustively
3. Write evidence to its designated workspace subdirectory with provenance citations: `<!-- cite: source=<type>, ref=<path>, confidence=<level>, agent=<role> -->`
4. Write a `.completed` marker with file count summary
5. On failure, write a `.failed` marker with error description

The 8 agents are:

```
  parallel IntelligenceParallel

  agent SourceAnalyzer
    label: "Source Code Analyzer"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are the Source Code Analyzer for Greenfield reverse engineering.

      ## Pre-flight
      If the file workspace/raw/source/.skipped exists, write "Source code analysis skipped — source not available" to workspace/raw/source/skipped-summary.md and stop.

      ## Your job
      Read EVERY source file in the target directory exhaustively. Do not skim. Do not skip "boring" sections.

      1. Read the full source tree structure first (use Glob to map all files)
      2. Chunk files by module/directory (not by line count)
      3. For each chunk, analyze: functions, classes, methods, control flow, state management, error handling
      4. Write per-chunk analysis to workspace/raw/source/analysis/chunk-NNNN.md
      5. Write a function index to workspace/raw/source/functions/index.md
      6. Write a manifest listing all evidence files to workspace/raw/source/manifest.md

      ## Provenance
      Every behavioral claim MUST have a provenance citation:
      <!-- cite: source=source-code, ref=workspace/raw/source/analysis/chunk-NNNN.md:LINE, confidence=inferred, agent=source-analyzer -->

      ## Completion
      On success: write workspace/raw/source/.completed with: "files: N, chunks: M"
      On failure: write workspace/raw/source/.failed with the error description

  agent DocResearcher
    label: "Documentation Researcher"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are the Documentation Researcher for Greenfield reverse engineering.

      ## Pre-flight
      If the file workspace/public/docs/.skipped exists, write "Doc research skipped — docs not available" to workspace/public/docs/skipped-summary.md and stop.

      ## Your job
      Read ALL documentation in the target: README files, docs/ directories, wikis, inline documentation, man pages, help text.

      1. Catalog all documentation sources found
      2. Extract behavioral descriptions, configuration docs, API docs, user guides
      3. Write evidence files to workspace/public/docs/ organized by topic
      4. Write a manifest to workspace/public/docs/manifest.md

      ## Provenance
      <!-- cite: source=docs, ref=workspace/public/docs/FILE:LINE, confidence=inferred, agent=doc-researcher -->

      ## Completion
      On success: write workspace/public/docs/.completed with file count
      On failure: write workspace/public/docs/.failed with error

  agent SdkAnalyzer
    label: "SDK Analyzer"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are the SDK Analyzer for Greenfield reverse engineering.

      ## Pre-flight
      If the file workspace/public/ecosystem/.skipped exists, write "SDK analysis skipped — no SDK deps found" to workspace/public/ecosystem/skipped-summary.md and stop.

      ## Your job
      Read package manifests (package.json, go.mod, Cargo.toml, pyproject.toml, etc.) and analyze SDK dependencies, integration patterns, and ecosystem relationships.

      1. Identify all external dependencies and their purposes
      2. Document SDK APIs being consumed and how
      3. Map integration patterns (HTTP clients, database drivers, auth libraries)
      4. Write evidence to workspace/public/ecosystem/

      ## Provenance
      <!-- cite: source=sdk, ref=workspace/public/ecosystem/FILE:LINE, confidence=inferred, agent=sdk-analyzer -->

      ## Completion
      On success: write workspace/public/ecosystem/.completed
      On failure: write workspace/public/ecosystem/.failed

  agent CommunityAnalyst
    label: "Community Intelligence Analyst"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are the Community Intelligence Analyst for Greenfield reverse engineering.

      ## Your job
      Search the web for public information about the target software: documentation sites, GitHub issues, discussions, blog posts, Stack Overflow questions, tutorials.

      Community analysis is ALWAYS available (web search). There is no skip marker for this source type.

      1. Search for the project name, key APIs, error messages
      2. Document community understanding of behavior, known issues, common patterns
      3. Write evidence to workspace/public/community/

      ## Provenance
      <!-- cite: source=community, ref=workspace/public/community/FILE:LINE, confidence=inferred, agent=community-analyst -->

      ## Completion
      On success: write workspace/public/community/.completed
      On failure: write workspace/public/community/.failed

  agent RuntimeObserver
    label: "Runtime Observer"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are the Runtime Observer for Greenfield reverse engineering.

      ## Pre-flight
      If the file workspace/raw/runtime/.skipped exists, write "Runtime observation skipped — no container runtime available" to workspace/raw/runtime/skipped-summary.md and stop.

      ## Your job
      Run the target software in a container and observe its behavior.

      1. Detect the entry point (CLI, web server, library)
      2. Build/install if needed
      3. Run the target in a container with MANDATORY security flags:
         docker run --network none --memory 2g --cpus 1.0 --read-only --tmpfs /tmp:rw,noexec,nosuid,size=512m --tmpfs /var/tmp:rw,noexec,nosuid,size=256m --security-opt no-new-privileges --pids-limit 256 "$IMAGE" "$CMD"
         These flags are NON-NEGOTIABLE. Never run containers without them.
      4. Exercise CLI flags, API endpoints, interactive commands
      5. Observe and document behavior, capture output
      6. Write evidence to workspace/raw/runtime/

      ## Provenance
      <!-- cite: source=runtime, ref=workspace/raw/runtime/FILE:LINE, confidence=confirmed, agent=runtime-observer -->

      ## Completion
      On success: write workspace/raw/runtime/.completed
      On failure: write workspace/raw/runtime/.failed

  agent BinaryAnalyzer
    label: "Binary Analyzer"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are the Binary Analyzer for Greenfield reverse engineering.

      ## Pre-flight
      If the file workspace/raw/binary/.skipped exists, write "Binary analysis skipped — no binaries found" to workspace/raw/binary/skipped-summary.md and stop.

      ## Your job
      Analyze binary files: decompile, extract symbols, trace execution paths.

      1. Check for available tools: objdump, radare2, ghidra (headless). Fall back to strings + file for minimal analysis
      2. Document symbol tables, string constants, linked libraries
      3. If decompilation is available, analyze control flow and data structures
      4. Write evidence to workspace/raw/binary/

      ## Provenance
      <!-- cite: source=binary, ref=workspace/raw/binary/FILE:LINE, confidence=inferred, agent=binary-analyzer -->

      ## Completion
      On success: write workspace/raw/binary/.completed
      On failure: write workspace/raw/binary/.failed

  agent GitArchaeologist
    label: "Git Archaeologist"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are the Git Archaeologist for Greenfield reverse engineering.

      ## Pre-flight
      If the file workspace/raw/project-history/.skipped exists, write "Git archaeology skipped — no git repo found" to workspace/raw/project-history/skipped-summary.md and stop.

      ## Your job
      Mine the git history for behavioral evidence: evolution patterns, deleted features, architectural decisions.

      1. Analyze git log for major changes, feature additions, bug fixes
      2. Use git blame on key files to understand evolution
      3. Look for deleted code that reveals past behavior
      4. Document architectural decisions visible in commit messages
      5. Write evidence to workspace/raw/project-history/

      ## Provenance
      <!-- cite: source=git-history, ref=workspace/raw/project-history/FILE:LINE, confidence=inferred, agent=git-archaeologist -->

      ## Completion
      On success: write workspace/raw/project-history/.completed
      On failure: write workspace/raw/project-history/.failed

  agent TestSuiteAnalyzer
    label: "Test Suite Analyzer"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are the Test Suite Analyzer for Greenfield reverse engineering.

      ## Pre-flight
      If the file workspace/raw/test-evidence/.skipped exists, write "Test suite analysis skipped — no tests found" to workspace/raw/test-evidence/skipped-summary.md and stop.

      ## Your job
      Read existing test suites for behavioral evidence. Tests are one of the best sources of behavioral specification.

      1. Read all test files exhaustively
      2. Extract behavioral assertions — what does each test verify?
      3. Run tests if possible and capture results
      4. Document test coverage: what behaviors are tested, what gaps exist
      5. Write evidence to workspace/raw/test-evidence/

      ## Provenance
      <!-- cite: source=tests, ref=workspace/raw/test-evidence/FILE:LINE, confidence=confirmed, agent=test-suite-analyzer -->

      ## Completion
      On success: write workspace/raw/test-evidence/.completed
      On failure: write workspace/raw/test-evidence/.failed

  fan_in IntelligenceJoin <- SourceAnalyzer, DocResearcher, SdkAnalyzer, CommunityAnalyst, RuntimeObserver, BinaryAnalyzer, GitArchaeologist, TestSuiteAnalyzer
```

And add the CoverageAgent after CoverageCheck:

```
  agent CoverageAgent
    label: "Coverage Review Agent"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Coverage Review Agent. You are invoked because fewer than 2 non-community intelligence sources produced results.

      Read workspace/discovery-manifest.yaml to see what sources were available.
      Read the .completed, .skipped, and .failed markers in workspace/raw/ and workspace/public/ to understand what happened.

      Your job:
      1. Assess whether the available evidence is sufficient for meaningful behavioral spec generation
      2. Identify any additional sources that might have been missed (e.g., docs embedded in source comments, tests in non-standard locations)
      3. If you find additional sources, analyze them and write evidence to the appropriate workspace directories
      4. Write a coverage assessment to workspace/raw/coverage-assessment.md

      HARD CONSTRAINT: If evidence is truly insufficient (binary-only with no decompiler, no docs, no community presence), report this clearly. Do not fabricate evidence.
```

- [ ] **Step 2: Replace edges with full fan-out/fan-in flow**

Replace the edges section with:

```
  edges
    Start -> ReadManifest
    ReadManifest -> WriteSkipMarkers  when ctx.tool_stdout startswith manifest-ready  label: manifest_ok
    ReadManifest -> Exit              when ctx.tool_stdout = no-manifest              label: no_manifest
    ReadManifest -> Exit
    WriteSkipMarkers -> IntelligenceParallel
    IntelligenceParallel -> SourceAnalyzer
    IntelligenceParallel -> DocResearcher
    IntelligenceParallel -> SdkAnalyzer
    IntelligenceParallel -> CommunityAnalyst
    IntelligenceParallel -> RuntimeObserver
    IntelligenceParallel -> BinaryAnalyzer
    IntelligenceParallel -> GitArchaeologist
    IntelligenceParallel -> TestSuiteAnalyzer
    SourceAnalyzer -> IntelligenceJoin
    DocResearcher -> IntelligenceJoin
    SdkAnalyzer -> IntelligenceJoin
    CommunityAnalyst -> IntelligenceJoin
    RuntimeObserver -> IntelligenceJoin
    BinaryAnalyzer -> IntelligenceJoin
    GitArchaeologist -> IntelligenceJoin
    TestSuiteAnalyzer -> IntelligenceJoin
    IntelligenceJoin -> CoverageCheck
    CoverageCheck -> CoverageAgent      when ctx.tool_stdout startswith coverage-  label: low_coverage
    CoverageCheck -> WriteL1Summary     when ctx.tool_stdout startswith coverage-  label: sufficient
    CoverageCheck -> Exit               when ctx.tool_stdout startswith incomplete label: fan_in_failed
    CoverageCheck -> WriteL1Summary
    CoverageAgent -> WriteL1Summary
    WriteL1Summary -> Exit
```

Note: The CoverageCheck routing needs refinement — the `low_coverage` edge should fire when `noncommunity-0` or `noncommunity-1` appears in the output. For simplicity, route CoverageAgent as a pass-through (it runs, then continues to WriteL1Summary regardless). The CoverageCheck → WriteL1Summary edge handles the sufficient-coverage case.

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield_discovery.dip 2>&1 | tail -3`
Expected: `valid with NN warning(s) (~20 nodes, ~28 edges)`

- [ ] **Step 4: Simulate**

Run: `tracker simulate greenfield_discovery.dip 2>&1 | head -30`
Expected: Shows Start → ReadManifest → WriteSkipMarkers → IntelligenceParallel → 8 agents → IntelligenceJoin → CoverageCheck → WriteL1Summary → Exit

- [ ] **Step 5: Commit**

```bash
git add greenfield_discovery.dip
git commit -m "feat(greenfield): add L1 intelligence agents with 8-way parallel fan-out"
```

---

### Task 3: Create greenfield_synthesis.dip — L2 synthesis + Synthesizer

**Files:**
- Create: `greenfield_synthesis.dip`

- [ ] **Step 1: Create the file with workflow header, tool nodes, L2 agents, and Synthesizer**

```
# ABOUTME: L2 synthesis + L3 deep specs + Gate 1/1b for Greenfield reverse engineering.
# ABOUTME: Synthesizes L1 evidence into module map, writes behavioral specs, verifies with quality gates.
workflow GreenfieldSynthesis
  goal: "Synthesize L1 evidence into a unified module map (L2), write deep behavioral specs (L3), and verify correctness and completeness via Gate 1 and Gate 1b quality gates."
  start: Start
  exit: Exit

  defaults
    max_restarts: 15
    fidelity: summary:medium

  agent Start
    label: Start
    max_turns: 1
    prompt:
      Acknowledge that the L2/L3 synthesis pipeline is starting. Report ready status.
      HARD CONSTRAINT: Do NOT read project files. Do NOT write code. Your ONLY job is to acknowledge start.

  agent Exit
    label: Exit
    max_turns: 1
    prompt:
      L2/L3 synthesis pipeline complete. Report final status.
      HARD CONSTRAINT: Do NOT write code. Do NOT modify files. Your ONLY job is to acknowledge completion.

  tool ReadL1Summary
    label: "Read L1 Summary"
    timeout: 10s
    command:
      set -eu
      if [ ! -f "workspace/raw/l1-summary.yaml" ]; then
        printf 'no-l1-summary'
        exit 0
      fi
      completed=$(yq '.completed_sources' "workspace/raw/l1-summary.yaml")
      printf 'l1-ready-%s-sources' "$completed"

  parallel SynthesisParallel

  agent FeatureDiscoverer
    label: "Feature Discoverer"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Feature Discoverer for Greenfield reverse engineering.

      Read ALL evidence in workspace/raw/ and workspace/public/ — source analysis, docs, SDK info, community intelligence, runtime observations, test evidence, git history.

      Build a comprehensive feature inventory:
      1. List every user-facing feature, CLI command, API endpoint, configuration option
      2. For each feature: name, description, behavioral summary, evidence sources
      3. Assign priority: P0 (critical), P1 (important), P2 (minor), P3 (edge case)
      4. Write the inventory to workspace/raw/synthesis/features/inventory.md

      Every claim needs provenance: <!-- cite: source=synthesis, ref=<evidence-path>, confidence=<level>, agent=feature-discoverer -->

  agent ArchitectureAnalyst
    label: "Architecture Analyst"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Architecture Analyst for Greenfield reverse engineering.

      Read ALL evidence in workspace/raw/ and workspace/public/.

      Infer the architecture model:
      1. Identify major components and their boundaries
      2. Map data flow between components
      3. Identify external interfaces (APIs, protocols, file formats)
      4. Document architectural patterns (MVC, microservices, event-driven, etc.)
      5. Write to workspace/raw/synthesis/architecture/

      Every claim needs provenance.

  agent ApiExtractor
    label: "API Extractor"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the API Extractor for Greenfield reverse engineering.

      Read ALL evidence in workspace/raw/ and workspace/public/.

      Extract every external API contract:
      1. CLI flags and commands (including hidden/debug ones)
      2. HTTP/gRPC/WebSocket endpoints with request/response formats
      3. Environment variables and configuration keys
      4. File format contracts (input/output)
      5. Write to workspace/raw/synthesis/api/

      Every claim needs provenance.

  agent ModuleMapper
    label: "Module Mapper"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Module Mapper for Greenfield reverse engineering.

      Read ALL evidence in workspace/raw/ and workspace/public/.

      Map code structure to behavioral domains:
      1. Identify logical modules/domains (not source file boundaries — behavioral boundaries)
      2. For each module: what behavior it owns, what it depends on, what depends on it
      3. Write module map to workspace/raw/synthesis/behavioral-summaries/

      Every claim needs provenance.

  fan_in SynthesisJoin <- FeatureDiscoverer, ArchitectureAnalyst, ApiExtractor, ModuleMapper

  agent Synthesizer
    label: "Synthesizer"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Synthesizer for Greenfield reverse engineering.

      Read all L2 outputs:
      - workspace/raw/synthesis/features/
      - workspace/raw/synthesis/architecture/
      - workspace/raw/synthesis/api/
      - workspace/raw/synthesis/behavioral-summaries/

      Merge them into a unified module map:
      1. Reconcile overlapping findings from the 4 L2 agents
      2. Resolve any contradictions (cite which evidence is stronger)
      3. Produce a single coherent module map with behavioral domains, interfaces, and dependencies
      4. Write to workspace/raw/synthesis/module-map.md

      This module map is the PRIMARY input for L3 deep spec agents. It must be comprehensive.
```

- [ ] **Step 2: Add basic edges**

```
  edges
    Start -> ReadL1Summary
    ReadL1Summary -> SynthesisParallel  when ctx.tool_stdout startswith l1-ready  label: l1_ok
    ReadL1Summary -> Exit               when ctx.tool_stdout = no-l1-summary      label: no_l1
    ReadL1Summary -> Exit
    SynthesisParallel -> FeatureDiscoverer
    SynthesisParallel -> ArchitectureAnalyst
    SynthesisParallel -> ApiExtractor
    SynthesisParallel -> ModuleMapper
    FeatureDiscoverer -> SynthesisJoin
    ArchitectureAnalyst -> SynthesisJoin
    ApiExtractor -> SynthesisJoin
    ModuleMapper -> SynthesisJoin
    SynthesisJoin -> Synthesizer
    Synthesizer -> Exit
```

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield_synthesis.dip 2>&1 | tail -3`
Expected: `valid` with ~10 nodes

- [ ] **Step 4: Commit**

```bash
git add greenfield_synthesis.dip
git commit -m "feat(greenfield): create synthesis pipeline with L2 agents and Synthesizer"
```

---

### Task 4: Add L3 deep specs + Gates to greenfield_synthesis.dip

**Files:**
- Modify: `greenfield_synthesis.dip`

- [ ] **Step 1: Add L3 agents between Synthesizer and Exit**

Add after the Synthesizer agent:

```
  parallel DeepSpecsParallel

  agent DeepDiveAnalyzer
    label: "Deep Dive Analyzer"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Deep Dive Analyzer for Greenfield reverse engineering.

      ## Input boundary
      Read L2 summary files ONLY — do NOT read raw L1 chunks:
      - workspace/raw/synthesis/module-map.md
      - workspace/raw/synthesis/features/
      - workspace/raw/synthesis/architecture/
      - workspace/raw/synthesis/api/
      - workspace/raw/synthesis/behavioral-summaries/

      ## Your job
      Write per-module behavioral specs. For each module in the module map:
      1. Describe what the module does (behavior, not implementation)
      2. Document all states, transitions, decision points
      3. Document error handling behavior
      4. Write to workspace/raw/specs/modules/<module-name>.md

      If workspace/raw/specs/gate1-findings.md exists, read it and address the findings.

      Every claim needs provenance: <!-- cite: source=synthesis, ref=<path>, confidence=<level>, agent=deep-dive-analyzer -->

  agent BehaviorDocumenter
    label: "Behavior Documenter"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Behavior Documenter for Greenfield reverse engineering.

      ## Input boundary
      Read L2 summary files ONLY (workspace/raw/synthesis/).

      Write behavioral documentation with provenance for each behavioral domain.
      Focus on observable behaviors, state machines, and decision logic.
      Write to workspace/raw/specs/modules/ (complement DeepDiveAnalyzer's output).

  agent UserJourneyAnalyzer
    label: "User Journey Analyzer"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the User Journey Analyzer for Greenfield reverse engineering.

      ## Input boundary
      Read L2 summary files ONLY (workspace/raw/synthesis/).

      Map end-to-end user journeys:
      1. Identify all entry points (CLI commands, API calls, UI interactions)
      2. Trace each journey from input to output
      3. Document happy paths and error paths
      4. Write to workspace/raw/specs/journeys/

      Every claim needs provenance.

  agent ContractExtractor
    label: "Contract Extractor"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Contract Extractor for Greenfield reverse engineering.

      ## Input boundary
      Read L2 summary files ONLY (workspace/raw/synthesis/).

      Extract dependency contracts and protocol specs:
      1. External API contracts (what the software calls)
      2. Internal protocol specs (wire formats, serialization)
      3. Dependency API contracts (what breaks if deps change)
      4. Write to workspace/raw/specs/contracts/

      Every claim needs provenance.

  fan_in DeepSpecsJoin <- DeepDiveAnalyzer, BehaviorDocumenter, UserJourneyAnalyzer, ContractExtractor
```

- [ ] **Step 2: Add Gate 1, Gate 1b, remediation, and summary nodes**

Add after DeepSpecsJoin:

```
  tool Gate1ToolCheck
    label: "Gate 1 Tool Check"
    timeout: 30s
    command:
      set -eu
      errors=""
      retries=0
      if [ -f "workspace/.gate1-retries" ]; then
        retries=$(cat "workspace/.gate1-retries")
      fi
      retries=$((retries + 1))
      printf '%s' "$retries" > "workspace/.gate1-retries"
      if [ "$retries" -gt 3 ]; then
        printf 'budget-exhausted'
        exit 0
      fi
      spec_count=$(find "workspace/raw/specs/modules/" -name "*.md" -print0 2>/dev/null | xargs -0 -I{} echo x | wc -l)
      if [ "$spec_count" -eq 0 ]; then errors="${errors}no-specs "; fi
      no_cite=$(find "workspace/raw/specs/modules/" -name "*.md" -print0 2>/dev/null | xargs -0 grep -rL "<!-- cite:" 2>/dev/null | wc -l)
      if [ "$no_cite" -gt 0 ]; then errors="${errors}missing-provenance-${no_cite}-files "; fi
      if [ ! -f "workspace/raw/synthesis/module-map.md" ]; then errors="${errors}no-module-map "; fi
      journey_count=$(find "workspace/raw/specs/journeys/" -name "*.md" -print0 2>/dev/null | xargs -0 -I{} echo x | wc -l)
      if [ "$journey_count" -eq 0 ]; then errors="${errors}no-journeys "; fi
      if [ -n "$errors" ]; then
        printf 'invalid-%s' "$errors"
        exit 0
      fi
      rm -f "workspace/.gate1-retries"
      printf 'gate1-pass'

  agent Gate1AgentReview
    label: "Gate 1 Agent Review"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    auto_status: true
    max_retries: 3
    retry_target: DeepDiveAnalyzer
    fallback_target: Gate1Failed
    prompt:
      You are the Gate 1 quality reviewer. Evaluate the behavioral specs in workspace/raw/specs/.

      Check for:
      1. Contradictions between specs
      2. Ratio of assumed vs confirmed claims (most should be confirmed or inferred)
      3. Constants and crypto values verified against evidence
      4. Overall spec quality and depth

      Write findings to workspace/raw/specs/gate1-findings.md.

      STATUS: success if specs are sound. STATUS: fail if material issues found.

  tool Gate1bCompleteness
    label: "Gate 1b Completeness Check"
    timeout: 30s
    command:
      set -eu
      retries=0
      if [ -f "workspace/.gate1b-retries" ]; then
        retries=$(cat "workspace/.gate1b-retries")
      fi
      retries=$((retries + 1))
      printf '%s' "$retries" > "workspace/.gate1b-retries"
      if [ "$retries" -gt 2 ]; then
        printf 'budget-exhausted'
        exit 0
      fi
      gaps=""
      if [ -d "workspace/raw/source/analysis" ]; then
        for chunk in workspace/raw/source/analysis/chunk-*.md; do
          [ -f "$chunk" ] || continue
          base=$(basename "$chunk")
          if ! grep -rq "$base" "workspace/raw/specs/" 2>/dev/null; then
            gaps="${gaps}${base} "
          fi
        done
      fi
      if [ -n "$gaps" ]; then
        printf 'gaps-%s' "$gaps"
        exit 0
      fi
      rm -f "workspace/.gate1b-retries"
      printf 'gate1b-pass'

  agent Gate1bAgent
    label: "Gate 1b Completeness Review"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    auto_status: true
    max_retries: 2
    retry_target: JourneyContractRemediation
    fallback_target: Gate1Failed
    prompt:
      You are the Gate 1b completeness reviewer. Verify every user-facing surface is captured in specs.

      Read the gap list from the Gate 1b tool check. Assess whether the gaps represent missing behavioral coverage or are benign (e.g., utility code with no user-facing behavior).

      Write findings to workspace/raw/specs/gate1b-findings.md.

      STATUS: success if coverage is adequate. STATUS: fail if material gaps exist.

  agent JourneyContractRemediation
    label: "Journey/Contract Remediation"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Journey/Contract Remediation agent. Gate 1b found completeness gaps.

      Read workspace/raw/specs/gate1b-findings.md.
      Read L2 synthesis files for context (workspace/raw/synthesis/).

      Write the missing journey/contract specs to fill the gaps. Do NOT re-run all L3 analysis — only fill the specific gaps identified.

      Write new specs to workspace/raw/specs/journeys/ or workspace/raw/specs/contracts/ as appropriate.

  tool WriteL2L3Summary
    label: "Write L2/L3 Summary"
    timeout: 10s
    command:
      set -eu
      spec_count=$(find "workspace/raw/specs/modules/" -name "*.md" 2>/dev/null | wc -l)
      journey_count=$(find "workspace/raw/specs/journeys/" -name "*.md" 2>/dev/null | wc -l)
      contract_count=$(find "workspace/raw/specs/contracts/" -name "*.md" 2>/dev/null | wc -l)
      printf 'summary-specs-%s-journeys-%s-contracts-%s' "$spec_count" "$journey_count" "$contract_count"

  agent Gate1Failed
    label: "Gate 1 Failed"
    max_turns: 1
    prompt:
      Gate 1 or Gate 1b has exhausted its retry budget. Read workspace/raw/specs/gate1-findings.md and/or gate1b-findings.md.
      Report what passed and what failed. Write workspace/.synthesis-failed with the failure reason.
      HARD CONSTRAINT: Do NOT fix anything. Report only.
```

- [ ] **Step 3: Update edges — replace `Synthesizer -> Exit` with full L3 + gate flow**

Replace the edges section:

```
  edges
    Start -> ReadL1Summary
    ReadL1Summary -> SynthesisParallel  when ctx.tool_stdout startswith l1-ready  label: l1_ok
    ReadL1Summary -> Exit               when ctx.tool_stdout = no-l1-summary      label: no_l1
    ReadL1Summary -> Exit
    SynthesisParallel -> FeatureDiscoverer
    SynthesisParallel -> ArchitectureAnalyst
    SynthesisParallel -> ApiExtractor
    SynthesisParallel -> ModuleMapper
    FeatureDiscoverer -> SynthesisJoin
    ArchitectureAnalyst -> SynthesisJoin
    ApiExtractor -> SynthesisJoin
    ModuleMapper -> SynthesisJoin
    SynthesisJoin -> Synthesizer
    Synthesizer -> DeepSpecsParallel
    DeepSpecsParallel -> DeepDiveAnalyzer
    DeepSpecsParallel -> BehaviorDocumenter
    DeepSpecsParallel -> UserJourneyAnalyzer
    DeepSpecsParallel -> ContractExtractor
    DeepDiveAnalyzer -> DeepSpecsJoin
    BehaviorDocumenter -> DeepSpecsJoin
    UserJourneyAnalyzer -> DeepSpecsJoin
    ContractExtractor -> DeepSpecsJoin
    DeepSpecsJoin -> Gate1ToolCheck
    Gate1ToolCheck -> Gate1AgentReview     when ctx.tool_stdout = gate1-pass        label: gate1_tool_pass
    Gate1ToolCheck -> Gate1AgentReview     when ctx.tool_stdout startswith invalid  label: gate1_tool_issues
    Gate1ToolCheck -> Gate1Failed          when ctx.tool_stdout = budget-exhausted  label: gate1_budget
    Gate1ToolCheck -> Gate1Failed
    Gate1AgentReview -> Gate1bCompleteness  when ctx.outcome = success  label: gate1_pass
    Gate1AgentReview -> Gate1Failed         when ctx.outcome = fail     label: gate1_fail
    Gate1AgentReview -> Gate1Failed
    Gate1bCompleteness -> Gate1bAgent       when ctx.tool_stdout startswith gaps    label: gaps_found
    Gate1bCompleteness -> WriteL2L3Summary  when ctx.tool_stdout = gate1b-pass      label: gate1b_pass
    Gate1bCompleteness -> Gate1Failed       when ctx.tool_stdout = budget-exhausted label: gate1b_budget
    Gate1bCompleteness -> WriteL2L3Summary
    Gate1bAgent -> WriteL2L3Summary  when ctx.outcome = success  label: gate1b_pass
    Gate1bAgent -> Gate1Failed       when ctx.outcome = fail     label: gate1b_fail
    Gate1bAgent -> Gate1Failed
    JourneyContractRemediation -> Gate1bCompleteness  restart: true
    WriteL2L3Summary -> Exit
    Gate1Failed -> Exit
```

- [ ] **Step 4: Validate**

Run: `tracker validate greenfield_synthesis.dip 2>&1 | tail -3`
Expected: `valid with NN warning(s) (~20 nodes, ~35 edges)`

- [ ] **Step 5: Commit**

```bash
git add greenfield_synthesis.dip
git commit -m "feat(greenfield): add L3 deep specs, Gate 1, Gate 1b with retry loops"
```

---

### Task 5: Create greenfield_validation.dip — L4 test vectors + Gate 2

**Files:**
- Create: `greenfield_validation.dip`

- [ ] **Step 1: Create file with workflow header, tools, L4 agents, and Gate 2**

```
# ABOUTME: L4 test vectors + Gate 2 + L5 sanitization for Greenfield reverse engineering.
# ABOUTME: Generates test vectors/acceptance criteria, reviews for leakage, sanitizes to output/.
workflow GreenfieldValidation
  goal: "Generate test vectors and acceptance criteria (L4), review for implementation leakage (Gate 2), and sanitize raw specs into clean output/ form (L5)."
  start: Start
  exit: Exit

  defaults
    max_restarts: 15
    fidelity: summary:medium

  agent Start
    label: Start
    max_turns: 1
    prompt:
      Acknowledge that the L4/L5 validation pipeline is starting. Report ready status.
      HARD CONSTRAINT: Do NOT read project files. Do NOT write code. Your ONLY job is to acknowledge start.

  agent Exit
    label: Exit
    max_turns: 1
    prompt:
      L4/L5 validation pipeline complete. Report final status.
      HARD CONSTRAINT: Your ONLY job is to acknowledge completion.

  tool ReadSpecs
    label: "Read Specs"
    timeout: 10s
    command:
      set -eu
      if [ ! -d "workspace/raw/specs/modules" ]; then
        printf 'no-specs'
        exit 0
      fi
      count=$(find "workspace/raw/specs/modules/" -name "*.md" 2>/dev/null | wc -l)
      if [ "$count" -eq 0 ]; then
        printf 'no-specs'
        exit 0
      fi
      printf 'specs-ready-%s-modules' "$count"

  parallel ValidationParallel

  agent TestVectorGenerator
    label: "Test Vector Generator"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      You are the Test Vector Generator for Greenfield reverse engineering.

      Read all behavioral specs in workspace/raw/specs/modules/ and workspace/raw/specs/journeys/.

      Generate Given/When/Then test vectors for every P0 behavioral claim:

      ### TV-MODULE-001: Description
      GIVEN: <precondition>
      WHEN: <action>
      THEN: <expected outcome>

      Also generate edge case vectors and dependency contract failure mode vectors.

      Write to workspace/raw/specs/test-vectors/

  agent TestGenerator
    label: "Test Spec Generator"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      You are the Test Spec Generator for Greenfield reverse engineering.

      Read all behavioral specs in workspace/raw/specs/.

      Generate runnable test spec outlines organized by module. These are skeleton test files an implementation team can flesh out.

      Write to workspace/raw/specs/test-vectors/test-specs/

  agent AcceptanceCriteriaWriter
    label: "Acceptance Criteria Writer"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      You are the Acceptance Criteria Writer for Greenfield reverse engineering.

      Read all behavioral specs in workspace/raw/specs/.

      Write formal acceptance criteria per module:

      ### AC-MODULE-001: Description
      GIVEN: <context>
      WHEN: <trigger>
      THEN: <observable result>
      Linked specs: [spec-module-behavior-name]

      Each AC must have a unique ID and link to the spec it validates.

      Write to workspace/raw/specs/validation/

  fan_in ValidationJoin <- TestVectorGenerator, TestGenerator, AcceptanceCriteriaWriter
```

Add Gate 2 tool check (full bash from spec) and Gate 2 agent:

```
  tool Gate2ToolCheck
    label: "Gate 2 Tool Check"
    timeout: 30s
    command:
      set -eu
      errors=""
      retries=0
      if [ -f "workspace/.gate2-retries" ]; then
        retries=$(cat "workspace/.gate2-retries")
      fi
      retries=$((retries + 1))
      printf '%s' "$retries" > "workspace/.gate2-retries"
      if [ "$retries" -gt 3 ]; then
        printf 'budget-exhausted'
        exit 0
      fi
      tv_count=$(find "workspace/raw/specs/test-vectors/" -name "*.md" -print0 2>/dev/null | xargs -0 -I{} echo x | wc -l)
      if [ "$tv_count" -eq 0 ]; then errors="${errors}no-test-vectors "; fi
      ac_count=$(find "workspace/raw/specs/validation/" -name "*.md" -print0 2>/dev/null | xargs -0 -I{} echo x | wc -l)
      if [ "$ac_count" -eq 0 ]; then errors="${errors}no-acceptance-criteria "; fi
      leak_pyjs=$(find "workspace/raw/specs/test-vectors/" -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "function \|def \|class \|import \|require(" 2>/dev/null | wc -l)
      leak_go=$(find "workspace/raw/specs/test-vectors/" -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "^func \|^package \|^import (" 2>/dev/null | wc -l)
      leak_rust=$(find "workspace/raw/specs/test-vectors/" -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "^fn \|^pub struct \|^impl \|^use " 2>/dev/null | wc -l)
      leak_c=$(find "workspace/raw/specs/test-vectors/" -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "^void \|^int \|^#include " 2>/dev/null | wc -l)
      leak_count=$((leak_pyjs + leak_go + leak_rust + leak_c))
      if [ "$leak_count" -gt 0 ]; then errors="${errors}leakage-${leak_count}-files "; fi
      ac_leak=$(find "workspace/raw/specs/validation/" -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "function \|def \|class \|^func \|^fn \|^void \|^int \|^#include " 2>/dev/null | wc -l)
      if [ "$ac_leak" -gt 0 ]; then errors="${errors}ac-leakage-${ac_leak}-files "; fi
      if [ -n "$errors" ]; then
        printf 'invalid-%s' "$errors"
        exit 0
      fi
      rm -f "workspace/.gate2-retries"
      printf 'gate2-pass'

  agent Gate2AgentReview
    label: "Gate 2 Agent Review"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    auto_status: true
    max_retries: 3
    retry_target: TestVectorGenerator
    fallback_target: Gate2Failed
    prompt:
      You are the Gate 2 quality reviewer. Review test vectors and acceptance criteria in workspace/raw/specs/.

      Check for:
      1. All P0 behaviors have test vectors
      2. Acceptance criteria have valid IDs and link to specs
      3. No implementation leakage in behavioral prose (code in examples is OK)
      4. Test vectors cover edge cases and error conditions

      Write findings to workspace/raw/specs/gate2-findings.md.

      STATUS: success if quality is adequate. STATUS: fail if material issues found.

  agent Gate2Failed
    label: "Gate 2 Failed"
    max_turns: 1
    prompt:
      Gate 2 has exhausted its retry budget. Report what passed and what failed.
      Write workspace/.validation-failed with the failure reason.
      HARD CONSTRAINT: Do NOT fix anything. Report only.
```

- [ ] **Step 2: Add edges for L4 + Gate 2 (L5 added in Task 6)**

```
  edges
    Start -> ReadSpecs
    ReadSpecs -> ValidationParallel  when ctx.tool_stdout startswith specs-ready  label: specs_ok
    ReadSpecs -> Exit                when ctx.tool_stdout = no-specs              label: no_specs
    ReadSpecs -> Exit
    ValidationParallel -> TestVectorGenerator
    ValidationParallel -> TestGenerator
    ValidationParallel -> AcceptanceCriteriaWriter
    TestVectorGenerator -> ValidationJoin
    TestGenerator -> ValidationJoin
    AcceptanceCriteriaWriter -> ValidationJoin
    ValidationJoin -> Gate2ToolCheck
    Gate2ToolCheck -> Gate2AgentReview     when ctx.tool_stdout = gate2-pass        label: gate2_tool_pass
    Gate2ToolCheck -> Gate2AgentReview     when ctx.tool_stdout startswith invalid  label: gate2_tool_issues
    Gate2ToolCheck -> Gate2Failed          when ctx.tool_stdout = budget-exhausted  label: gate2_budget
    Gate2ToolCheck -> Gate2Failed
    Gate2AgentReview -> Exit       when ctx.outcome = success  label: gate2_pass
    Gate2AgentReview -> Gate2Failed when ctx.outcome = fail     label: gate2_fail
    Gate2AgentReview -> Gate2Failed
    Gate2Failed -> Exit
```

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield_validation.dip 2>&1 | tail -3`
Expected: `valid` with ~12 nodes

- [ ] **Step 4: Commit**

```bash
git add greenfield_validation.dip
git commit -m "feat(greenfield): create validation pipeline with L4 agents and Gate 2"
```

---

### Task 6: Add L5 sanitizers to greenfield_validation.dip

**Files:**
- Modify: `greenfield_validation.dip`

- [ ] **Step 1: Add L5 sanitizer agents, SanitizationToolCheck, and WriteL4L5Summary**

Add after Gate2Failed:

```
  parallel SanitizationParallel

  agent SanitizerSpecs
    label: "Sanitizer — Specs"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are a Sanitizer worker for Greenfield. Rewrite raw behavioral specs to output form.

      Read workspace/raw/specs/modules/ and workspace/raw/specs/journeys/.
      Write sanitized versions to workspace/output/specs/.

      PRESERVE: environment variables, CLI flags, config keys, API fields, protocol names, error messages, user-facing paths.
      REMOVE: function names, variable names, minified identifiers, line numbers, source file paths, code structure descriptions.

      Provenance citations survive — but replace raw source paths with workspace-relative refs.

      You REWRITE from understanding, not copy. The output must read as if written by someone who knows the behavior but never saw the code.

  agent SanitizerTestVectors
    label: "Sanitizer — Test Vectors"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are a Sanitizer worker for Greenfield. Sanitize test vectors.

      Read workspace/raw/specs/test-vectors/.
      Write sanitized versions to workspace/output/test-vectors/.

      Same PRESERVE/REMOVE rules as spec sanitization. Test vectors should describe behavior (Given/When/Then) without referencing internal code.

  agent SanitizerAcceptanceCriteria
    label: "Sanitizer — Acceptance Criteria"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are a Sanitizer worker for Greenfield. Sanitize acceptance criteria.

      Read workspace/raw/specs/validation/.
      Write sanitized versions to workspace/output/validation/acceptance-criteria/.

      Same PRESERVE/REMOVE rules. AC IDs and spec links must be preserved.

  fan_in SanitizationJoin <- SanitizerSpecs, SanitizerTestVectors, SanitizerAcceptanceCriteria

  tool SanitizationToolCheck
    label: "Sanitization Check"
    timeout: 15s
    command:
      set -eu
      errors=""
      spec_count=$(find "workspace/output/specs/" -name "*.md" -print0 2>/dev/null | xargs -0 -I{} echo x | wc -l)
      if [ "$spec_count" -eq 0 ]; then errors="${errors}no-output-specs "; fi
      tv_count=$(find "workspace/output/test-vectors/" -name "*.md" -print0 2>/dev/null | xargs -0 -I{} echo x | wc -l)
      if [ "$tv_count" -eq 0 ]; then errors="${errors}no-output-test-vectors "; fi
      ac_count=$(find "workspace/output/validation/" -name "*.md" -print0 2>/dev/null | xargs -0 -I{} echo x | wc -l)
      if [ "$ac_count" -eq 0 ]; then errors="${errors}no-output-acceptance-criteria "; fi
      if [ -n "$errors" ]; then
        printf 'sanitization-incomplete-%s' "$errors"
        exit 0
      fi
      printf 'sanitization-ok-specs-%s-tv-%s-ac-%s' "$spec_count" "$tv_count" "$ac_count"

  tool WriteL4L5Summary
    label: "Write L4/L5 Summary"
    timeout: 10s
    command:
      set -eu
      raw_specs=$(find "workspace/raw/specs/modules/" -name "*.md" 2>/dev/null | wc -l)
      output_specs=$(find "workspace/output/specs/" -name "*.md" 2>/dev/null | wc -l)
      tv=$(find "workspace/output/test-vectors/" -name "*.md" 2>/dev/null | wc -l)
      ac=$(find "workspace/output/validation/" -name "*.md" 2>/dev/null | wc -l)
      printf 'l4l5-done-raw-%s-output-%s-tv-%s-ac-%s' "$raw_specs" "$output_specs" "$tv" "$ac"
```

- [ ] **Step 2: Update edges — change Gate2AgentReview success to route through L5**

Change `Gate2AgentReview -> Exit when ctx.outcome = success` to route through sanitization:

```
    Gate2AgentReview -> SanitizationParallel  when ctx.outcome = success  label: gate2_pass
    Gate2AgentReview -> Gate2Failed            when ctx.outcome = fail     label: gate2_fail
    Gate2AgentReview -> Gate2Failed
    SanitizationParallel -> SanitizerSpecs
    SanitizationParallel -> SanitizerTestVectors
    SanitizationParallel -> SanitizerAcceptanceCriteria
    SanitizerSpecs -> SanitizationJoin
    SanitizerTestVectors -> SanitizationJoin
    SanitizerAcceptanceCriteria -> SanitizationJoin
    SanitizationJoin -> SanitizationToolCheck
    SanitizationToolCheck -> WriteL4L5Summary  when ctx.tool_stdout startswith sanitization-ok  label: sanitization_ok
    SanitizationToolCheck -> Gate2Failed       when ctx.tool_stdout startswith sanitization-incomplete  label: sanitization_failed
    SanitizationToolCheck -> WriteL4L5Summary
    WriteL4L5Summary -> Exit
```

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield_validation.dip 2>&1 | tail -3`
Expected: `valid with NN warning(s) (~16 nodes)`

- [ ] **Step 4: Commit**

```bash
git add greenfield_validation.dip
git commit -m "feat(greenfield): add L5 sanitizers with post-sanitization check"
```

---

### Task 7: Create greenfield_review.dip — L6 reviewers

**Files:**
- Create: `greenfield_review.dip`

- [ ] **Step 1: Create file with workflow header, tools, L6 reviewers, and L6 gate**

```
# ABOUTME: L6 second-pass review + L7 fidelity validation for Greenfield reverse engineering.
# ABOUTME: Independent review of sanitized output for contamination and fidelity loss.
workflow GreenfieldReview
  goal: "Review sanitized output specs for implementation contamination (L6) and behavioral fidelity loss (L7). Remediate findings. Also serves the /sanitize re-run use case."
  start: Start
  exit: Exit

  defaults
    max_restarts: 15
    fidelity: summary:medium

  agent Start
    label: Start
    max_turns: 1
    prompt:
      Acknowledge that the L6/L7 review pipeline is starting.
      HARD CONSTRAINT: Your ONLY job is to acknowledge start.

  agent Exit
    label: Exit
    max_turns: 1
    prompt:
      L6/L7 review pipeline complete. Report final status.
      HARD CONSTRAINT: Your ONLY job is to acknowledge completion.

  tool ReadSanitizedOutput
    label: "Read Sanitized Output"
    timeout: 10s
    command:
      set -eu
      if [ ! -d "workspace/output/specs" ]; then
        printf 'no-output'
        exit 0
      fi
      count=$(find "workspace/output/specs/" -name "*.md" 2>/dev/null | wc -l)
      if [ "$count" -eq 0 ]; then
        printf 'no-output'
        exit 0
      fi
      mkdir -p "workspace/review"
      printf 'output-ready-%s-specs' "$count"

  parallel ReviewParallel

  agent StructuralLeakageReviewer
    label: "Structural Leakage Reviewer"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      You are the Structural Leakage Reviewer. Look for code structure bleeding through in workspace/output/.

      Check for: module boundaries matching source tree structure, internal naming patterns, file path references, code organization leaking into spec organization.

      Write findings to workspace/review/l6-structural-leakage.md using format:
      ## Finding F-001
      **Severity:** high | medium | low
      **Location:** <file>
      **Issue:** <description>
      **Evidence:** <the offending text>
      **Recommendation:** <fix>

  agent ContentContaminationReviewer
    label: "Content Contamination Reviewer"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      You are the Content Contamination Reviewer. Look for variable names, file paths, identifiers, and minified symbols in workspace/output/.

      Write findings to workspace/review/l6-content-contamination.md using the same format.

  agent BehavioralCompletenessReviewer
    label: "Behavioral Completeness Reviewer"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      You are the Behavioral Completeness Reviewer. Compare workspace/output/ spec count and coverage against workspace/raw/specs/.

      Check that nothing was lost during sanitization. Every behavioral domain in raw/ should have a corresponding domain in output/.

      Write findings to workspace/review/l6-behavioral-completeness.md.

  agent DeepReadAuditor
    label: "Deep Read Auditor"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      You are the Deep Read Auditor. Line-by-line audit of workspace/output/specs/ for any contamination the other reviewers might have missed.

      Write findings to workspace/review/l6-deep-read-audit.md.

  fan_in ReviewJoin <- StructuralLeakageReviewer, ContentContaminationReviewer, BehavioralCompletenessReviewer, DeepReadAuditor

  tool L6ToolCheck
    label: "L6 Tool Check"
    timeout: 30s
    command:
      set -eu
      retries=0
      if [ -f "workspace/.l6-retries" ]; then
        retries=$(cat "workspace/.l6-retries")
      fi
      retries=$((retries + 1))
      printf '%s' "$retries" > "workspace/.l6-retries"
      if [ "$retries" -gt 3 ]; then
        printf 'budget-exhausted'
        exit 0
      fi
      high=$(find "workspace/review/" -name "l6-*.md" -print0 2>/dev/null | xargs -0 grep -c "^\*\*Severity:\*\* high" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      medium=$(find "workspace/review/" -name "l6-*.md" -print0 2>/dev/null | xargs -0 grep -c "^\*\*Severity:\*\* medium" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      low=$(find "workspace/review/" -name "l6-*.md" -print0 2>/dev/null | xargs -0 grep -c "^\*\*Severity:\*\* low" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      if [ "$high" -gt 0 ]; then
        printf 'l6-has-findings-high-%s-medium-%s-low-%s' "$high" "$medium" "$low"
        exit 0
      fi
      if [ "$medium" -gt 0 ] || [ "$low" -gt 0 ]; then
        printf 'l6-has-findings-medium-%s-low-%s' "$medium" "$low"
        exit 0
      fi
      rm -f "workspace/.l6-retries"
      printf 'l6-clean'

  agent L6AgentVerdict
    label: "L6 Verdict"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    auto_status: true
    max_retries: 3
    retry_target: RemediateL6
    fallback_target: L6Failed
    prompt:
      You are the L6 verdict agent. Review the findings in workspace/review/l6-*.md.

      If high-severity contamination exists, STATUS: fail.
      If only medium/low findings, use judgment — medium findings may be acceptable with notes.
      If no findings, STATUS: success.

  agent RemediateL6
    label: "Remediate L6 Findings"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the L6 Remediation agent. Fix contamination flagged by L6 reviewers.

      Read workspace/review/l6-*.md for findings.
      Rewrite ONLY the affected sections in workspace/output/. Preserve everything else.
      Do not reintroduce contamination while fixing.

  agent L6Failed
    label: "L6 Failed"
    max_turns: 1
    prompt:
      L6 review has exhausted its retry budget. Report findings.
      Write workspace/.review-failed with the failure reason.
      HARD CONSTRAINT: Report only.
```

- [ ] **Step 2: Add L6 edges**

```
  edges
    Start -> ReadSanitizedOutput
    ReadSanitizedOutput -> ReviewParallel  when ctx.tool_stdout startswith output-ready  label: output_ok
    ReadSanitizedOutput -> Exit            when ctx.tool_stdout = no-output              label: no_output
    ReadSanitizedOutput -> Exit
    ReviewParallel -> StructuralLeakageReviewer
    ReviewParallel -> ContentContaminationReviewer
    ReviewParallel -> BehavioralCompletenessReviewer
    ReviewParallel -> DeepReadAuditor
    StructuralLeakageReviewer -> ReviewJoin
    ContentContaminationReviewer -> ReviewJoin
    BehavioralCompletenessReviewer -> ReviewJoin
    DeepReadAuditor -> ReviewJoin
    ReviewJoin -> L6ToolCheck
    L6ToolCheck -> L6AgentVerdict     when ctx.tool_stdout startswith l6-  label: l6_check
    L6ToolCheck -> L6Failed           when ctx.tool_stdout = budget-exhausted  label: l6_budget
    L6ToolCheck -> L6AgentVerdict
    L6AgentVerdict -> Exit       when ctx.outcome = success  label: l6_pass
    L6AgentVerdict -> L6Failed   when ctx.outcome = fail     label: l6_fail
    L6AgentVerdict -> L6Failed
    RemediateL6 -> L6ToolCheck   restart: true
    L6Failed -> Exit
```

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield_review.dip 2>&1 | tail -3`
Expected: `valid` with ~14 nodes

- [ ] **Step 4: Commit**

```bash
git add greenfield_review.dip
git commit -m "feat(greenfield): create review pipeline with L6 reviewers and remediation"
```

---

### Task 8: Add L7 fidelity validators to greenfield_review.dip

**Files:**
- Modify: `greenfield_review.dip`

- [ ] **Step 1: Add L7 validators, gate, remediation, and summary nodes**

Add after L6Failed:

```
  parallel FidelityParallel

  agent FidelityValidatorSpecs
    label: "Fidelity Validator — Specs"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Fidelity Validator for specs. Compare workspace/raw/specs/ against workspace/output/specs/.

      Flag where behavioral detail was lost or weakened during sanitization.

      Write findings to workspace/review/l7-fidelity-specs.md:
      ## Fidelity Flag FL-001
      **Raw spec:** <file>
      **Output spec:** <file>
      **Lost detail:** <description>
      **Severity:** critical | notable | minor
      **Recommendation:** <how to restore without reintroducing contamination>

  agent FidelityValidatorTestVectors
    label: "Fidelity Validator — Test Vectors"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Fidelity Validator for test vectors. Compare workspace/raw/specs/test-vectors/ against workspace/output/test-vectors/.

      Flag where test assertions were weakened or test scenarios were lost.

      Write findings to workspace/review/l7-fidelity-test-vectors.md using the same format.

  fan_in FidelityJoin <- FidelityValidatorSpecs, FidelityValidatorTestVectors

  tool L7ToolCheck
    label: "L7 Tool Check"
    timeout: 30s
    command:
      set -eu
      retries=0
      if [ -f "workspace/.l7-retries" ]; then
        retries=$(cat "workspace/.l7-retries")
      fi
      retries=$((retries + 1))
      printf '%s' "$retries" > "workspace/.l7-retries"
      if [ "$retries" -gt 3 ]; then
        printf 'budget-exhausted'
        exit 0
      fi
      critical=$(find "workspace/review/" -name "l7-*.md" -print0 2>/dev/null | xargs -0 grep -c "^\*\*Severity:\*\* critical" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      notable=$(find "workspace/review/" -name "l7-*.md" -print0 2>/dev/null | xargs -0 grep -c "^\*\*Severity:\*\* notable" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      minor=$(find "workspace/review/" -name "l7-*.md" -print0 2>/dev/null | xargs -0 grep -c "^\*\*Severity:\*\* minor" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      if [ "$critical" -gt 0 ]; then
        printf 'l7-has-flags-critical-%s-notable-%s-minor-%s' "$critical" "$notable" "$minor"
        exit 0
      fi
      if [ "$notable" -gt 0 ] || [ "$minor" -gt 0 ]; then
        printf 'l7-has-flags-notable-%s-minor-%s' "$notable" "$minor"
        exit 0
      fi
      rm -f "workspace/.l7-retries"
      printf 'l7-clean'

  agent L7AgentVerdict
    label: "L7 Verdict"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    auto_status: true
    max_retries: 3
    retry_target: RemediateL7
    fallback_target: L7Failed
    prompt:
      You are the L7 fidelity verdict agent. Review workspace/review/l7-*.md.

      If critical fidelity flags exist (behavioral detail meaningfully lost), STATUS: fail.
      If only notable/minor flags, use judgment.
      If no flags, STATUS: success.

  agent RemediateL7
    label: "Remediate L7 Findings"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the L7 Remediation agent. Restore behavioral detail that was over-sanitized.

      Read workspace/review/l7-*.md for fidelity flags.
      Restore lost detail in workspace/output/ WITHOUT reintroducing implementation contamination.
      This is the hardest job in the pipeline — balance fidelity against cleanliness.

  agent L7Failed
    label: "L7 Failed"
    max_turns: 1
    prompt:
      L7 fidelity validation has exhausted its retry budget. Report findings.
      Write workspace/.review-failed with the failure reason.
      HARD CONSTRAINT: Report only.

  tool WriteReviewSummary
    label: "Write Review Summary"
    timeout: 10s
    command:
      set -eu
      l6_findings=$(find "workspace/review/" -name "l6-*.md" -print0 2>/dev/null | xargs -0 grep -c "## Finding" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      l7_flags=$(find "workspace/review/" -name "l7-*.md" -print0 2>/dev/null | xargs -0 grep -c "## Fidelity Flag" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      printf 'review-done-l6-findings-%s-l7-flags-%s' "$l6_findings" "$l7_flags"
```

- [ ] **Step 2: Update edges — change L6 success to route through L7**

Change `L6AgentVerdict -> Exit when ctx.outcome = success` to:

```
    L6AgentVerdict -> FidelityParallel  when ctx.outcome = success  label: l6_pass
```

Add L7 edges:

```
    FidelityParallel -> FidelityValidatorSpecs
    FidelityParallel -> FidelityValidatorTestVectors
    FidelityValidatorSpecs -> FidelityJoin
    FidelityValidatorTestVectors -> FidelityJoin
    FidelityJoin -> L7ToolCheck
    L7ToolCheck -> L7AgentVerdict     when ctx.tool_stdout startswith l7-  label: l7_check
    L7ToolCheck -> L7Failed           when ctx.tool_stdout = budget-exhausted  label: l7_budget
    L7ToolCheck -> L7AgentVerdict
    L7AgentVerdict -> WriteReviewSummary  when ctx.outcome = success  label: l7_pass
    L7AgentVerdict -> L7Failed            when ctx.outcome = fail     label: l7_fail
    L7AgentVerdict -> L7Failed
    RemediateL7 -> L7ToolCheck   restart: true
    WriteReviewSummary -> Exit
    L7Failed -> Exit
```

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield_review.dip 2>&1 | tail -3`
Expected: `valid with NN warning(s) (~16 nodes)`

- [ ] **Step 4: Commit**

```bash
git add greenfield_review.dip
git commit -m "feat(greenfield): add L7 fidelity validators with remediation loop"
```

---

### Task 9: Create greenfield.dip — runner skeleton + setup tools

**Files:**
- Create: `greenfield.dip`

- [ ] **Step 1: Create file with workflow header, Start/Exit, setup tools, and DiscoverTargetReview**

```
# ABOUTME: Top-level runner for Greenfield reverse engineering pipeline.
# ABOUTME: Chains 4 layer subgraphs (discovery, synthesis, validation, review) with state checks.
workflow Greenfield
  goal: "Reverse engineer a target codebase into clean behavioral specs, test vectors, and acceptance criteria via a 7-layer pipeline with quality gates."
  start: Start
  exit: Exit

  defaults
    max_restarts: 5
    fidelity: summary:medium

  agent Start
    label: Start
    max_turns: 1
    prompt:
      Acknowledge that the Greenfield reverse engineering pipeline is starting.
      HARD CONSTRAINT: Your ONLY job is to acknowledge start.

  agent Exit
    label: Exit
    max_turns: 1
    prompt:
      Greenfield pipeline complete. Report final status.
      HARD CONSTRAINT: Your ONLY job is to acknowledge completion.

  tool SetupWorkspace
    label: "Setup Workspace"
    timeout: 30s
    command:
      set -eu
      mkdir -p workspace/public/docs workspace/public/ecosystem workspace/public/community
      mkdir -p workspace/raw/source/chunks workspace/raw/source/analysis workspace/raw/source/functions workspace/raw/source/manifests workspace/raw/source/exploration
      mkdir -p workspace/raw/runtime/cli workspace/raw/runtime/web workspace/raw/runtime/behaviors workspace/raw/runtime/ux-flows workspace/raw/runtime/visual
      mkdir -p workspace/raw/binary workspace/raw/project-history workspace/raw/test-evidence
      mkdir -p workspace/raw/synthesis/features workspace/raw/synthesis/architecture workspace/raw/synthesis/api workspace/raw/synthesis/behavioral-summaries
      mkdir -p workspace/raw/specs/modules workspace/raw/specs/journeys workspace/raw/specs/contracts workspace/raw/specs/test-vectors workspace/raw/specs/validation
      mkdir -p workspace/output/specs workspace/output/test-vectors workspace/output/validation/acceptance-criteria
      mkdir -p workspace/provenance/sessions workspace/review
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      printf '{"target": ".", "started_at": "%s", "excluded_sources": [], "pipeline_version": "1.0"}\n' "$now" > workspace/workspace.json
      printf 'workspace-ready'

  tool DiscoverTarget
    label: "Discover Target"
    timeout: 30s
    command:
      set -eu
      src=false; docs=false; sdk=false; runtime=false; binary=false; git=false; tests=false; visual=false; contracts=false
      count=1
      if find . -maxdepth 3 -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.c" -o -name "*.cpp" -o -name "*.rb" 2>/dev/null | head -1 | grep -q .; then
        src=true; count=$((count + 1))
      fi
      if [ -d docs ] || [ -d doc ] || find . -maxdepth 2 -name "README*" 2>/dev/null | head -1 | grep -q .; then
        docs=true; count=$((count + 1))
      fi
      if [ -f package.json ] || [ -f go.mod ] || [ -f Cargo.toml ] || [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f Gemfile ]; then
        sdk=true; count=$((count + 1))
      fi
      if command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; then
        runtime=true; count=$((count + 1))
      fi
      if find . -maxdepth 2 -name "*.exe" -o -name "*.so" -o -name "*.dylib" -o -name "*.dll" 2>/dev/null | head -1 | grep -q .; then
        binary=true; count=$((count + 1))
      fi
      if [ -d .git ]; then
        git=true; count=$((count + 1))
      fi
      if find . -maxdepth 3 -name "*test*" -o -name "*spec*" 2>/dev/null | head -1 | grep -q .; then
        tests=true; count=$((count + 1))
      fi
      if find . -maxdepth 3 -name "*.html" -o -name "*.jsx" -o -name "*.tsx" -o -name "*.vue" -o -name "*.svelte" 2>/dev/null | head -1 | grep -q .; then
        visual=true; count=$((count + 1))
      fi
      if find . -maxdepth 3 -name "*.proto" -o -name "openapi*" -o -name "swagger*" -o -name "*.graphql" 2>/dev/null | head -1 | grep -q .; then
        contracts=true; count=$((count + 1))
      fi
      noncommunity=$((count - 1))
      printf 'target: "."\nsources:\n  source_code: %s\n  docs: %s\n  sdk: %s\n  community: true\n  runtime: %s\n  binary: %s\n  git_history: %s\n  tests: %s\n  visual: %s\n  contracts: %s\nsource_count: %s\n' "$src" "$docs" "$sdk" "$runtime" "$binary" "$git" "$tests" "$visual" "$contracts" "$count" > workspace/discovery-manifest.yaml
      printf 'discovered-%s-sources-noncommunity-%s' "$count" "$noncommunity"

  agent DiscoverTargetReview
    label: "Discovery Review"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are the Discovery Review agent. The automated target discovery found fewer than 2 non-community source types.

      Read workspace/discovery-manifest.yaml. Then examine the target directory manually — look for sources the automated probe may have missed:
      - Documentation in non-standard locations
      - Tests with non-standard naming
      - Source code in unexpected languages or locations
      - Embedded docs in source comments

      If you find additional sources, update workspace/discovery-manifest.yaml accordingly.
```

- [ ] **Step 2: Add initial edges**

```
  edges
    Start -> SetupWorkspace
    SetupWorkspace -> DiscoverTarget
    DiscoverTarget -> DiscoverTargetReview  when ctx.tool_stdout endswith noncommunity-0  label: very_low_coverage
    DiscoverTarget -> DiscoverTargetReview  when ctx.tool_stdout endswith noncommunity-1  label: low_coverage
    DiscoverTarget -> Exit                  when ctx.tool_stdout startswith discovered     label: sufficient
    DiscoverTarget -> Exit
    DiscoverTargetReview -> Exit
```

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield.dip 2>&1 | tail -3`
Expected: `valid` with ~5 nodes

- [ ] **Step 4: Commit**

```bash
git add greenfield.dip
git commit -m "feat(greenfield): create runner skeleton with workspace setup and target discovery"
```

---

### Task 10: Add subgraph refs + state checks to greenfield.dip

**Files:**
- Modify: `greenfield.dip`

- [ ] **Step 1: Add subgraph refs, Check* tools, FinalReport, and failure nodes**

Add after DiscoverTargetReview:

```
  subgraph L1_Discovery
    ref: greenfield_discovery.dip

  tool CheckL1Output
    label: "Check L1 Output"
    timeout: 15s
    command:
      set -eu
      if [ -f "workspace/.l1-failed" ]; then
        printf 'l1-failed-%s' "$(cat workspace/.l1-failed)"
        exit 0
      fi
      completed=0
      dirs="workspace/raw/source workspace/public/docs workspace/public/ecosystem workspace/public/community workspace/raw/runtime workspace/raw/binary workspace/raw/project-history workspace/raw/test-evidence"
      for d in $dirs; do
        if [ -f "$d/.completed" ]; then
          completed=$((completed + 1))
        fi
      done
      if [ "$completed" -eq 0 ]; then
        printf 'l1-empty'
        exit 0
      fi
      printf 'l1-ok-%s-sources' "$completed"

  subgraph L2L3_Synthesis
    ref: greenfield_synthesis.dip

  tool CheckSynthesisOutput
    label: "Check Synthesis Output"
    timeout: 15s
    command:
      set -eu
      if [ -f "workspace/.synthesis-failed" ]; then
        printf 'synthesis-failed-%s' "$(cat workspace/.synthesis-failed)"
        exit 0
      fi
      specs=$(find "workspace/raw/specs/modules/" -name "*.md" 2>/dev/null | wc -l)
      if [ "$specs" -eq 0 ]; then
        printf 'synthesis-empty'
        exit 0
      fi
      printf 'synthesis-ok-%s-specs' "$specs"

  subgraph L4L5_Validation
    ref: greenfield_validation.dip

  tool CheckValidationOutput
    label: "Check Validation Output"
    timeout: 15s
    command:
      set -eu
      if [ -f "workspace/.validation-failed" ]; then
        printf 'validation-failed-%s' "$(cat workspace/.validation-failed)"
        exit 0
      fi
      output_specs=$(find "workspace/output/specs/" -name "*.md" 2>/dev/null | wc -l)
      tv=$(find "workspace/output/test-vectors/" -name "*.md" 2>/dev/null | wc -l)
      ac=$(find "workspace/output/validation/" -name "*.md" 2>/dev/null | wc -l)
      if [ "$output_specs" -eq 0 ] || [ "$tv" -eq 0 ] || [ "$ac" -eq 0 ]; then
        printf 'validation-incomplete-specs-%s-tv-%s-ac-%s' "$output_specs" "$tv" "$ac"
        exit 0
      fi
      printf 'validation-ok'

  subgraph L6L7_Review
    ref: greenfield_review.dip

  agent FinalReport
    label: "Final Report"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    max_turns: 3
    prompt:
      You are the Final Report agent. The Greenfield pipeline has completed all 7 layers.

      Read workspace/workspace.json, workspace/raw/l1-summary.yaml, and the output directory.

      Summarize:
      1. Target analyzed and sources discovered
      2. Number of behavioral specs produced
      3. Number of test vectors and acceptance criteria
      4. Gate results (all passed)
      5. Overall confidence assessment
      6. Output location: workspace/output/

  agent DiscoveryFailed
    label: "Discovery Failed"
    max_turns: 1
    prompt:
      L1 discovery subgraph failed. Write workspace/.l1-failed with reason. Report.

  agent L1Failed
    label: "L1 Output Check Failed"
    max_turns: 1
    prompt:
      L1 output check failed — no intelligence sources produced results. Report.

  agent SynthesisFailed
    label: "Synthesis Failed"
    max_turns: 1
    prompt:
      L2/L3 synthesis failed. Check workspace/.synthesis-failed for details. Report.

  agent ValidationFailed
    label: "Validation Failed"
    max_turns: 1
    prompt:
      L4/L5 validation failed. Check workspace/.validation-failed for details. Report.

  agent ReviewFailed
    label: "Review Failed"
    max_turns: 1
    prompt:
      L6/L7 review failed. Check workspace/.review-failed for details. Report.
```

- [ ] **Step 2: Replace edges with full runner flow**

```
  edges
    Start -> SetupWorkspace
    SetupWorkspace -> DiscoverTarget
    DiscoverTarget -> DiscoverTargetReview  when ctx.tool_stdout endswith noncommunity-0  label: very_low_coverage
    DiscoverTarget -> DiscoverTargetReview  when ctx.tool_stdout endswith noncommunity-1  label: low_coverage
    DiscoverTarget -> L1_Discovery          when ctx.tool_stdout startswith discovered     label: sufficient
    DiscoverTarget -> L1_Discovery
    DiscoverTargetReview -> L1_Discovery
    L1_Discovery -> CheckL1Output           when ctx.outcome = success  label: l1_done
    L1_Discovery -> DiscoveryFailed         when ctx.outcome = fail     label: l1_subgraph_failed
    L1_Discovery -> DiscoveryFailed
    CheckL1Output -> L2L3_Synthesis         when ctx.tool_stdout startswith l1-ok  label: l1_ok
    CheckL1Output -> L1Failed               when ctx.tool_stdout startswith l1-    label: l1_problem
    CheckL1Output -> L1Failed
    L2L3_Synthesis -> CheckSynthesisOutput   when ctx.outcome = success  label: synthesis_done
    L2L3_Synthesis -> SynthesisFailed        when ctx.outcome = fail     label: synthesis_subgraph_failed
    L2L3_Synthesis -> SynthesisFailed
    CheckSynthesisOutput -> L4L5_Validation  when ctx.tool_stdout startswith synthesis-ok  label: synthesis_ok
    CheckSynthesisOutput -> SynthesisFailed  when ctx.tool_stdout startswith synthesis-    label: synthesis_problem
    CheckSynthesisOutput -> SynthesisFailed
    L4L5_Validation -> CheckValidationOutput  when ctx.outcome = success  label: validation_done
    L4L5_Validation -> ValidationFailed       when ctx.outcome = fail     label: validation_subgraph_failed
    L4L5_Validation -> ValidationFailed
    CheckValidationOutput -> L6L7_Review      when ctx.tool_stdout = validation-ok  label: validation_ok
    CheckValidationOutput -> ValidationFailed when ctx.tool_stdout startswith validation-  label: validation_problem
    CheckValidationOutput -> ValidationFailed
    L6L7_Review -> FinalReport                when ctx.outcome = success  label: review_done
    L6L7_Review -> ReviewFailed               when ctx.outcome = fail     label: review_subgraph_failed
    L6L7_Review -> ReviewFailed
    FinalReport -> Exit
    DiscoveryFailed -> Exit
    L1Failed -> Exit
    SynthesisFailed -> Exit
    ValidationFailed -> Exit
    ReviewFailed -> Exit
```

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield.dip 2>&1 | tail -3`
Expected: `valid with NN warning(s) (~14 nodes)`

- [ ] **Step 4: Commit**

```bash
git add greenfield.dip
git commit -m "feat(greenfield): add subgraph refs, state checks, failure nodes to runner"
```

---

### Task 11: Cross-pipeline validation

**Files:**
- Validate: all 5 `.dip` files

- [ ] **Step 1: Validate all 5 pipelines**

```bash
tracker validate greenfield.dip 2>&1 | tail -3
tracker validate greenfield_discovery.dip 2>&1 | tail -3
tracker validate greenfield_synthesis.dip 2>&1 | tail -3
tracker validate greenfield_validation.dip 2>&1 | tail -3
tracker validate greenfield_review.dip 2>&1 | tail -3
```

Expected: All five report `valid`.

- [ ] **Step 2: Simulate all 5 pipelines**

```bash
tracker simulate greenfield.dip 2>&1 | tail -15
tracker simulate greenfield_discovery.dip 2>&1 | tail -10
tracker simulate greenfield_synthesis.dip 2>&1 | tail -10
tracker simulate greenfield_validation.dip 2>&1 | tail -10
tracker simulate greenfield_review.dip 2>&1 | tail -10
```

Expected: Complete simulation output with no errors.

- [ ] **Step 3: Verify subgraph refs resolve**

```bash
ls -la greenfield_discovery.dip greenfield_synthesis.dip greenfield_validation.dip greenfield_review.dip greenfield.dip
```

- [ ] **Step 4: Count nodes and compare against spec estimates**

```bash
echo "=== Greenfield pipelines ==="
tracker validate greenfield.dip 2>&1 | grep "valid"
tracker validate greenfield_discovery.dip 2>&1 | grep "valid"
tracker validate greenfield_synthesis.dip 2>&1 | grep "valid"
tracker validate greenfield_validation.dip 2>&1 | grep "valid"
tracker validate greenfield_review.dip 2>&1 | grep "valid"
```

Expected estimates from spec:
- greenfield.dip: ~14 nodes
- greenfield_discovery.dip: ~20 nodes
- greenfield_synthesis.dip: ~20 nodes
- greenfield_validation.dip: ~16 nodes
- greenfield_review.dip: ~16 nodes
- Total: ~86 nodes

- [ ] **Step 5: Commit if any fixes were needed**

Only commit if changes were made during validation.

---

### Task 12: Provider probe stubs

**Files:**
- Modify: `greenfield_discovery.dip`, `greenfield_synthesis.dip`, `greenfield_validation.dip`, `greenfield_review.dip`

- [ ] **Step 1: Document provider probe pattern**

Each subgraph's Start node should note in comments which provider it depends on:

- `greenfield_discovery.dip` — depends on Gemini (L1 agents), Anthropic (CoverageAgent)
- `greenfield_synthesis.dip` — depends on Anthropic (all agents)
- `greenfield_validation.dip` — depends on OpenAI (L4, Gate 2), Anthropic (L5 sanitizers)
- `greenfield_review.dip` — depends on OpenAI (L6 reviewers, verdicts), Anthropic (remediation, L7 validators)

Provider availability checking is a runtime concern — tracker handles provider probes before dispatching agents. The DIP pipeline does not need explicit probe tool nodes; tracker retries agent calls with exponential backoff on provider failures.

Add a comment block to each file documenting the provider dependency:

```
  # PROVIDER DEPENDENCIES:
  # Primary: gemini (L1 intelligence agents)
  # Fallback: anthropic (CoverageAgent)
  # See spec section "Provider Outage Handling" for fallback strategies.
```

- [ ] **Step 2: Validate all 5 after comments**

```bash
tracker validate greenfield_discovery.dip greenfield_synthesis.dip greenfield_validation.dip greenfield_review.dip greenfield.dip 2>&1 | grep "valid"
```

- [ ] **Step 3: Commit**

```bash
git add greenfield_discovery.dip greenfield_synthesis.dip greenfield_validation.dip greenfield_review.dip
git commit -m "docs(greenfield): add provider dependency comments to all subgraph pipelines"
```

---

### Task 13: Final verification and summary

**Files:**
- All 5 `.dip` files

- [ ] **Step 1: Verify git status is clean**

```bash
git status
```

Expected: Clean working tree.

- [ ] **Step 2: Review the full commit log**

```bash
git log --oneline main..HEAD
```

Expected: Shows the sequence of greenfield commits.

- [ ] **Step 3: Run tracker doctor on all 5 pipelines**

```bash
tracker doctor greenfield.dip 2>&1 | tail -5
tracker doctor greenfield_discovery.dip 2>&1 | tail -5
tracker doctor greenfield_synthesis.dip 2>&1 | tail -5
tracker doctor greenfield_validation.dip 2>&1 | tail -5
tracker doctor greenfield_review.dip 2>&1 | tail -5
```

Expected: Pipeline file checks pass. Provider probes may warn (environment-dependent).

- [ ] **Step 4: Final node count summary**

Record the actual node/edge counts for all 5 files and compare against the spec's estimates:

| File | Spec Estimate | Actual |
|---|---|---|
| greenfield.dip | ~14 nodes | ? nodes, ? edges |
| greenfield_discovery.dip | ~20 nodes | ? nodes, ? edges |
| greenfield_synthesis.dip | ~20 nodes | ? nodes, ? edges |
| greenfield_validation.dip | ~16 nodes | ? nodes, ? edges |
| greenfield_review.dip | ~16 nodes | ? nodes, ? edges |
| **Total** | **~86** | **?** |
