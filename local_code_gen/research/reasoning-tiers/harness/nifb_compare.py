"""
nifb_compare.py — quality comparison of full-dip NIFB runs at different reasoning configs.
Compares an ALL-LOW run's contract.md + sprint specs against the v3 default baseline (same raw
NIFB spec, full spec_to_sprints dip via tracker). An Opus judge scores the candidate contract
against the reference on the load-bearing dimensions, then spot-checks sprint-spec completeness.
Usage: python nifb_compare.py <candidate_run_dir> [reference_run_dir]
"""
import os, sys, json, glob, anthropic

PR = "/Users/michaelsugimura/Documents/GitHub/pipelines/experiments"
CAND_DIR = sys.argv[1] if len(sys.argv) > 1 else f"{PR}/nifb_full_run_alllow"
REF_DIR  = sys.argv[2] if len(sys.argv) > 2 else f"{PR}/nifb_full_run_v3"
A = anthropic.Anthropic()

def read(p): return open(p).read() if os.path.exists(p) else ""
ref_contract  = read(f"{REF_DIR}/.ai/contract.md")
cand_contract = read(f"{CAND_DIR}/.ai/contract.md")

import re as _re
def sprint_stats(d):
    # prefer enriched sprint specs; fall back to the architect's sprint_descriptions.jsonl
    files = sorted(glob.glob(f"{d}/.ai/sprints/SPRINT-*.md"))
    out = []
    if files:
        for f in files:
            t = read(f)
            out.append(dict(name=os.path.basename(f), lines=t.count("\n"),
                has_newfiles="## New files" in t or "New files:" in t,
                has_tests="Test plan" in t or "## Test" in t or "test plan" in t.lower(),
                has_crossmod="cross-module" in t.lower() or "cross_module" in t.lower(),
                has_imports="Imports" in t or "from app" in t or "import " in t,
                frs=set(_re.findall(r'FR\d+', t))))
    else:
        jl = read(f"{d}/.ai/sprint_descriptions.jsonl")
        for line in jl.splitlines():
            if not line.strip(): continue
            try: rec = json.loads(line)
            except Exception: continue
            t = rec.get("description","")
            out.append(dict(name=rec.get("path","?"), lines=t.count("\\n"),
                has_newfiles="New Files" in t or "New files" in t,
                has_tests="Test" in t or "DoD" in t or "test" in t.lower(),
                has_crossmod="cross-module" in t.lower() or "cross_module" in t.lower(),
                has_imports="import" in t.lower() or "from " in t,
                frs=set(_re.findall(r'FR\d+', t))))
    return out

RUBRIC = """You are auditing a software "architectural contract" from a multi-sprint code-generation pipeline.
Below: (1) a REFERENCE contract from the established default/high-reasoning pipeline run, and (2) a CANDIDATE
contract from an ALL-LOW-reasoning run of the SAME pipeline on the SAME source spec. Both were produced by the
real multi-turn architect (writes contract.md via a write tool, not single-shot).

Score the CANDIDATE 0-5 on each dimension (5 = equivalent-or-better than reference; 0 = absent/wrong), one-sentence why:
1. PATTERN_DECISION — explicit Pattern A/B choice with rationale; defensible for the project.
2. SECTION_COMPLETENESS — all required sections present and non-stub (Stack, Conventions, Data Model, Test Infra, File-Ownership, Symbol Ownership, Dependency Edges+cross-module tests, Mandatory Rules, Tricky Semantics).
3. SYMBOL_PINNING — cross-sprint types pinned with EXACT field names+types + relationship annotations (back_populates, lazy), no "...etc." gaps. THE #1 failure mode.
4. DEFECT_CLOSURE — build-system block verbatim, error class + JSON wire shape, StaticPool + check_same_thread, settings singleton (get_settings, no class-attr), nested-closure override fixtures.
5. CROSS_MODULE_TESTS — for each cross-sprint edge, a named cross-module test with a body sketch via the real upstream public API.
6. CONCRETENESS — decisive choices (no "you may use X or Y"), exact field sets, runtime-symptom cross-refs.

Then:
- OVERALL: 0-5 — would the candidate drive multi-sprint generation as well as the reference?
- VERDICT: "EQUIVALENT" / "MINOR_GAPS" / "MATERIAL_REGRESSION" + one-line reason.
- TOP_RISK: single most important omission/weakening vs reference (or "none").

Strict JSON: {"pattern_decision":{"score":N,"why":""},"section_completeness":{...},"symbol_pinning":{...},"defect_closure":{...},"cross_module_tests":{...},"concreteness":{...},"overall":N,"verdict":"","top_risk":""}
"""

def judge():
    if not cand_contract:
        print("[ERROR] no candidate contract.md yet at", CAND_DIR); return None
    msg = RUBRIC + "\n\n===REFERENCE CONTRACT (default baseline)===\n" + ref_contract + \
          "\n\n===CANDIDATE CONTRACT (all-low)===\n" + cand_contract
    with A.messages.stream(model="claude-opus-4-6", max_tokens=4000,
        messages=[{"role":"user","content":msg}],
        extra_body={"thinking":{"type":"adaptive"},"output_config":{"effort":"high"}}) as s:
        r = s.get_final_message()
    txt = "".join(b.text for b in r.content if getattr(b,"type","")=="text")
    i,e = txt.find("{"), txt.rfind("}")
    try: return json.loads(txt[i:e+1])
    except Exception: print("parse fail:\n", txt[:600]); return {"raw":txt}

if __name__ == "__main__":
    print(f"CANDIDATE: {CAND_DIR}\nREFERENCE: {REF_DIR}\n")
    print(f"contract.md lines: candidate={cand_contract.count(chr(10))}  reference={ref_contract.count(chr(10))}")
    cs, rs = sprint_stats(CAND_DIR), sprint_stats(REF_DIR)
    print(f"\nsprint specs: candidate={len(cs)}  reference={len(rs)}")
    def agg(s):
        n=len(s) or 1
        frs=set().union(*[x['frs'] for x in s]) if s else set()
        return dict(n=len(s), frs_covered=len(frs), with_tests=sum(x['has_tests'] for x in s),
                    with_crossmod=sum(x['has_crossmod'] for x in s), with_newfiles=sum(x['has_newfiles'] for x in s))
    print(f"  candidate agg: {agg(cs)}")
    print(f"  reference agg: {agg(rs)}")
    cf=set().union(*[x['frs'] for x in cs]) if cs else set()
    rf=set().union(*[x['frs'] for x in rs]) if rs else set()
    print(f"  FRs in reference but MISSING from candidate: {sorted(rf-cf, key=lambda x:int(x[2:])) or 'none'}")
    print(f"  FRs in candidate but not reference: {sorted(cf-rf, key=lambda x:int(x[2:])) or 'none'}")
    v = judge()
    if v and "overall" in v:
        print(f"\n=== CONTRACT JUDGE === OVERALL={v['overall']}/5  VERDICT={v['verdict']}")
        for k in ["pattern_decision","section_completeness","symbol_pinning","defect_closure","cross_module_tests","concreteness"]:
            print(f"   {k:22s} {v[k]['score']}/5  {v[k]['why']}")
        print(f"   TOP_RISK: {v['top_risk']}")
    json.dump(dict(candidate=CAND_DIR, reference=REF_DIR, judge=v,
                   cand_sprints=agg(cs), ref_sprints=agg(rs)),
              open(os.path.expanduser("~/reasoning_test/nifb_compare_result.json"),"w"), indent=2)
    print("\nCOMPARE DONE")
