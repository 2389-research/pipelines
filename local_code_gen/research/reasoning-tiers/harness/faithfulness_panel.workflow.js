// Faithfulness judge panel for the reasoning-tier study.
// Run via the Workflow tool. This is a Workflow SCRIPT, not a standalone ES module:
// top-level `await`, `return`, and the injected `agent()/parallel()/phase()/log()/args`
// globals are provided by the Workflow runtime (do NOT "fix" the top-level return).
//
// PORTABLE — no machine paths. Pass everything via the Workflow `args` input:
//   args = {
//     transcript: "<abs path to source spec transcript .md>",
//     email:      "<abs path to source spec email .md>",     // optional 2nd spec doc
//     plans: { high: "<path>", medium: "<path>", low: "<path>",
//              hybrid: "<path>", medlow: "<path>" },          // sprint_plan.md per config
//     frCounts: { high: 22, medium: 35, low: 34, hybrid: 27, medlow: 19 }  // optional, for the correlation question
//   }
// Any config keys present in `plans` are scored; pass all five to reproduce the study.

export const meta = {
  name: 'faithfulness-panel',
  description: 'Judge panel scoring each sprint-plan config for faithfulness to the source spec (paths via args)',
  phases: [
    { title: 'Panel', detail: 'N plans x 3 faithfulness lenses, each judge reads the source spec as ground truth' },
    { title: 'Synthesize', detail: 'aggregate panel scores + consensus missed/invented per config' },
  ],
}

if (!args || !args.transcript || !args.plans || Object.keys(args.plans).length === 0) {
  throw new Error('faithfulness-panel: pass args = {transcript, email?, plans:{key:path,...}, frCounts?}. See header for the schema.')
}
const SPEC = args.transcript
const EMAIL = args.email || null
const PLANS = Object.entries(args.plans).map(([key, path]) => ({ key, path }))
const FR_COUNTS = args.frCounts || {}

const LENSES = [
  { key: 'completeness', focus: 'COMPLETENESS lens: your job is to find REAL requirements in the source spec that are MISSING or only weakly covered in the sprint plan. Be exhaustive about omissions. A requirement is "real" only if a reasonable reader finds it in the spec as something the SOFTWARE SYSTEM must do.' },
  { key: 'scope_discipline', focus: 'SCOPE-DISCIPLINE lens: your job is to find sprints/requirements in the plan that DO NOT trace to the source spec — i.e. invented scope, OR action-items / research tasks / process notes / design principles miscast as system features (e.g. "make a PII-free spreadsheet", "review the prototype"). Splitting one real requirement into several finer ones is NOT a violation — only flag items with no real product-requirement basis in the spec.' },
  { key: 'holistic', focus: 'HOLISTIC FAITHFULNESS lens: judge overall how faithfully the plan represents the spec — neither missing real requirements nor inventing/miscasting non-requirements. Granularity (more FRs) is fine if each traces to a real requirement; judge fidelity, not count.' },
]
const SCHEMA = {
  type: 'object',
  properties: {
    faithfulness: { type: 'number', description: '0-10 overall faithfulness of this plan to the spec from your lens (10 = every real req covered, nothing invented/miscast)' },
    missed_real_requirements: { type: 'array', items: { type: 'string' }, description: 'real spec requirements missing/weak in this plan' },
    invented_or_miscast_items: { type: 'array', items: { type: 'string' }, description: 'plan items with no real product-requirement basis in the spec' },
    notes: { type: 'string', description: 'one or two sentence rationale' },
  },
  required: ['faithfulness', 'missed_real_requirements', 'invented_or_miscast_items', 'notes'],
}

phase('Panel')
const specRefs = `SOURCE SPEC (read in full): \`${SPEC}\`` + (EMAIL ? ` and \`${EMAIL}\`` : '')
const jobs = PLANS.flatMap(p => LENSES.map(l => () =>
  agent(
    `You are a faithfulness judge applying ONE specific lens. Read the SOURCE SPEC (ground truth) and the candidate SPRINT PLAN, then judge the plan AGAINST the spec.\n\n` +
    `${specRefs}\nCANDIDATE SPRINT PLAN: \`${p.path}\`\n\n` +
    `Use the Read tool to read all files in full before judging. Do NOT assume the plan's own requirement numbering is correct — verify each against the spec.\n\n` +
    `${l.focus}\n\n` +
    `Return your structured judgment. faithfulness is 0-10. Be concrete and name the actual requirement or sprint item.`,
    { label: `${p.key}:${l.key}`, phase: 'Panel', schema: SCHEMA }
  ).then(v => ({ plan: p.key, lens: l.key, ok: true, ...v }))
   .catch(e => ({ plan: p.key, lens: l.key, ok: false, error: String(e && e.message || e) }))
))
const raw = await parallel(jobs)
const panel = raw.filter(r => r && r.ok)
const failures = raw.filter(r => r && !r.ok)
if (failures.length) log(`⚠️ ${failures.length}/${raw.length} judge job(s) FAILED — aggregate is partial: ` + failures.map(f => `${f.plan}:${f.lens}`).join(', '))

// aggregate per plan; flag any plan whose lens coverage is incomplete (so a degraded panel isn't read as clean)
const byPlan = {}
for (const r of panel) {
  const b = (byPlan[r.plan] ||= { scores: [], missed: [], invented: [], lenses: {} })
  b.scores.push(r.faithfulness)
  b.missed.push(...r.missed_real_requirements)
  b.invented.push(...r.invented_or_miscast_items)
  b.lenses[r.lens] = { faithfulness: r.faithfulness, notes: r.notes }
}
const agg = {}
for (const [k, b] of Object.entries(byPlan)) {
  const mean = b.scores.reduce((a, c) => a + c, 0) / b.scores.length
  agg[k] = {
    mean_faithfulness: Math.round(mean * 10) / 10,
    per_lens: b.scores,
    lenses_scored: b.scores.length,
    lenses_expected: LENSES.length,
    fr_count: FR_COUNTS[k] ?? null,
    n_missed_flags: b.missed.length,
    n_invented_flags: b.invented.length,
    lenses: b.lenses,
  }
}
log('Panel aggregate: ' + Object.entries(agg).map(([k, v]) => `${k}=${v.mean_faithfulness}/10 (FRs:${v.fr_count ?? '?'} lenses:${v.lenses_scored}/${v.lenses_expected})`).join('  '))

phase('Synthesize')
const synthesis = await agent(
  `You are synthesizing a judge-panel faithfulness assessment of ${Object.keys(agg).length} sprint-plan configs produced from the same spec at different reasoning levels (config keys describe the reasoning of analyze_spec/tournament; e.g. "medlow" = medium analyze + low tournament). Each config was scored by ${LENSES.length} independent judges (completeness, scope-discipline, holistic lenses) reading the source spec as ground truth.\n\n` +
  (failures.length ? `NOTE: ${failures.length} judge job(s) failed; treat any config with lenses_scored < lenses_expected as having a partial score.\n\n` : '') +
  `FR count per config (use this to assess the count-vs-faithfulness question — do NOT guess counts): ${JSON.stringify(FR_COUNTS)}\n\n` +
  `Raw panel results (JSON):\n${JSON.stringify(panel, null, 2)}\n\n` +
  `Aggregate (JSON, includes fr_count per config):\n${JSON.stringify(agg, null, 2)}\n\n` +
  `Produce: (1) a ranking of the configs by faithfulness with mean scores and their FR counts; (2) for each config, the CONSENSUS missed real requirements (flagged by >=2 lenses or clearly real) and the CONSENSUS invented/miscast items; (3) using the supplied FR counts, a clear verdict on whether higher FR count correlated with worse faithfulness or not (the central question); (4) a one-paragraph recommendation on which reasoning config to use for analyze_spec given that the tournament is reasoning-insensitive. Be concise and decisive.`,
  { phase: 'Synthesize' }
)

return { aggregate: agg, failures, synthesis }
