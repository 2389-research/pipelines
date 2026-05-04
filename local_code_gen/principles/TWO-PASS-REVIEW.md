# Two-Pass Review

The architect's process for shipping a sprint spec. Pass 1 produces; Pass 2 scrutinizes.

## Why two passes

Pass 1 alone tends to produce a spec that **looks right** but contains subtle ambiguities qwen will fill in wrong. Pass 2's job is to actively look for those ambiguities — places where two reasonable interpretations exist, places where structural sections conflict with prose rules, places where a value that needs uniqueness wasn't pinned.

Validated on sprint 003 (Apr 30, 2026): Pass 1 produced a spec that looked clean. Pass 2 caught 3 ambiguities (request-field semantics, second-volunteer values, return-shape under add_member) that would have produced 1-2 test failures each. Pass 2 missed 1 ambiguity (defect class 14 — assertion-path mismatch with handler shape) which surfaced at runtime — added to the Pass-2 checklist below.

## Pass 1: convert architect input to speedrun format with all 14 defect-class rules pre-applied

Inputs:
- `.ai/sprint_plan.md` (or equivalent — the project decomposition)
- `.ai/spec_analysis.md` (or equivalent — FR-numbered requirements)
- `.ai/contract.md` (cross-sprint type/symbol ownership map — written ONCE for the project)
- For sprints 002+: prior SPRINT-NNN.md files (read for symbol references, not re-defined)

Outputs:
- `SPRINT-NNN.md` in speedrun format (see [`SPEEDRUN-SPEC-FORMAT.md`](SPEEDRUN-SPEC-FORMAT.md))

Pass 1 must apply the 14 defect-class rules from [`DEFECT-CLASSES.md`](DEFECT-CLASSES.md) preemptively:

- Imports listed as full Python statements per file
- Path/query types specified as Python annotations
- Collection routes use empty-string path `""`
- Static routes declared before parameterized routes (in BOTH the rule AND the API table)
- Algorithm sections that construct Read schemas list exact field sets
- Tests take fixtures as parameters (no inline construction)
- Test contract uses correct response-shape assertion paths
- Tricky semantics section names: lazy="selectin", monkeypatch on instance, closure scope, settings singleton, etc.
- Verbatim section for tiny config-shaped files
- Rules section reinforces tricky semantics + adds negative constraints

## Pass 2: scrutinize for ambiguity and conflict

Read the Pass-1 output as if you were qwen — what could you misinterpret?

### Pass 2 checklist

For each section of the spec, check:

#### Tricky semantics

- [ ] Each rule has a WHY (what runtime symptom occurs without it)?
- [ ] Each rule names the exact symbol/value it pins?
- [ ] Are there overlapping rules that contradict?

#### Data contract

- [ ] Every collection-side relationship has `lazy="selectin"`?
- [ ] Every bidirectional relationship has `back_populates` on both sides?
- [ ] Every Mapped[type] uses the imported type form (not bare module)?
- [ ] Are there fields that look like "common sense additions" qwen might invent? (E.g., a `Shift.station_id` that isn't actually in the contract — pin against this with an explicit "no other fields" rule.)

#### API contract

- [ ] Every path/query parameter has its Python type explicit?
- [ ] When parameterized + static paths share a prefix, are they ordered (static first) in the table?
- [ ] Collection routes use empty-string path `""`?
- [ ] Auth-required routes flagged with the dependency listed?

#### Algorithm

- [ ] Each step references types/exceptions by exact name?
- [ ] When constructing a Read schema explicitly, is the EXACT field set listed (with "no other fields")?
- [ ] When the request body has a field whose value isn't validated, is that explicit ("the field's value is NOT validated, the act of POSTing indicates intent")?
- [ ] When 4xx errors have a precedence (e.g., 404-before-403), is the ordering called out?

#### Test contract

- [ ] Each test takes the right fixtures as parameters?
- [ ] Each assert uses the correct response-shape path?
- [ ] When a test creates a second instance of a model with unique constraints (second volunteer, second location), are the EXACT distinguishing values specified to avoid collision with the fixture's primary instance?
- [ ] Idempotent-test asserts compare by capturing pre-state and post-state — names what to capture?
- [ ] Dates/times/UUIDs in JSON bodies serialized via `.isoformat()` / `str(...)`?
- [ ] String UUIDs from JSON responses parsed via `uuid.UUID(...)` before ORM queries?

#### Cross-section consistency

- [ ] Does the API contract table's route order match what the Algorithm sections imply?
- [ ] Do the Imports lists for each file actually cover every symbol the Algorithm references?
- [ ] Does the Test contract's response-shape assertions match the exception handler's actual JSON output?
- [ ] Are FROZEN files cross-referenced consistently between sprint 001 and current sprint?
- [ ] Do "this sprint's New files" cleanly NOT overlap with prior sprints' files?

#### Structural-vs-prose check (defect 11-bis)

- [ ] If Rules section says "X must come before Y," do all structural sections (table, signatures, algorithm subsections) reflect that ordering?
- [ ] If Rules section says a field has a specific shape, do all examples and Verbatim files use that shape?
- [ ] If Tricky semantics rule says "always do X," is X consistently applied across the spec?

## When Pass 2 finds something

- If it's a real ambiguity, patch the spec section that matters (often: tighten a rule, add an explicit value, restructure a section, add a Pass 1 rule that wasn't applied).
- If it's a defect class we haven't seen before, add it to [`DEFECT-CLASSES.md`](DEFECT-CLASSES.md) and update the Pass 2 checklist above.
- The point isn't to make the spec perfect — it's to **make the local generator's output deterministic enough to be reliable**.

## Pass 2 ROI

Empirically (NIFB sprint 003): Pass 2 caught 3 of 4 latent failures. Each would have been ~1 test failure → 1 LocalFix round per failure → ~30 sec wall time + qwen call. Pass 2 review took ~5 min of architect time. **Net: Pass 2 paid for itself 3-6× over** vs. running and patching.

The one Pass 2 missed (assertion-path mismatch — defect 14) only surfaced at runtime. The fix was cheap once observed (3 tests failed identically; one spec patch + regen of 2 files). Worth ~5 min wall time + 1 cloud call. Pass 2's checklist now includes the assertion-path-vs-handler-shape consistency check; this won't be missed twice.

## Pass 2 frequency

Run Pass 2 on EVERY sprint, not just complex ones. The simplest-looking sprints often have the subtlest gaps because the architect doesn't think to look.
