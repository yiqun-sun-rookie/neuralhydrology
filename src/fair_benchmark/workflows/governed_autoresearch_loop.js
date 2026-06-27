// THE canonical GOVERNED autonomous-research loop. Unlike an ad-hoc loop, it wires
// the four firewalls into the live orchestration so they cannot be bypassed:
//   - GOVERN phase: self-scans THIS script for cages/menus (autonomy firewall); aborts
//     if the loop itself is caged.
//   - Each candidate is scored through run_candidate, which enforces the governance
//     preflight (no active cages + a grounded novelty.yaml) and writes the
//     tamper-evident, hash-chained ledger (results firewall).
//   - CONCLUDE phase: every round verdict is routed through the conclusions gate into
//     registry/conclusions.md (a scored round -> evidence-based; an unscored/estimate
//     round -> hypothesis with a settling test).
// The strategist is genuinely open: propose or invent ANY method; only the fairness
// budget (constraints.yaml invariants) bounds it. Compute is consent-gated, not capped.
// Run:  Workflow({scriptPath: ".../governed_autoresearch_loop.js", args: {n: 2}})
export const meta = {
  name: 'governed-autoresearch-loop',
  description: 'Canonical governed autonomous-research loop: self-scans for cages, scores via run_candidate (preflight + hash-chained ledger), routes every verdict through the conclusions gate. The open strategist may invent any method within only the fairness budget; compute is consent-gated, not capped.',
  phases: [
    { title: 'Govern', detail: 'self-scan this script for cages/menus; abort if the loop is caged' },
    { title: 'Round 1', detail: 'open strategist -> implementer builds+runs+scores via run_candidate' },
    { title: 'Round 2', detail: 'strategist adapts to the round-1 real verdict' },
    { title: 'Conclude', detail: 'route each round verdict through the conclusions gate' },
  ],
}

const REPO = 'G:\\github\\pycharm\\projects\\neuralhydrology'
const SELF = REPO + '\\src\\fair_benchmark\\workflows\\governed_autoresearch_loop.js'
const LEDGER = 'src/fair_benchmark/registry/portfolio_ledger.csv'
const CONCLUSIONS = 'src/fair_benchmark/registry/conclusions.md'
const N = (args && args.n) || 2

const CONTRACT = `THE CONTEST (Track-0): 531 CAMELS-US basins, predict DAILY streamflow (mm/day) over EVAL 1989-10-01..1999-09-30. Allowed inputs ONLY: 5 Maurer forcings + 27 static attributes. Eval-period observed discharge is held by the scorer; training MAY use train-period (1999-10-01..2008-09-30) obs. Metric: median NSE (recomputed from held obs). Baseline to beat: LSTM 8-seed ensemble ~0.759.

REPO ${REPO} (Git Bash; run with 'export PYTHONPATH=src' from repo root). Leakage-safe layout the runner expects: experiments/<EXP>/{train.py (optional, reads train obs), model/, submission/predict.py (reads ONLY the bundle + ../../model/; emits basin,date,qsim for all 531 basins over eval), submission/predictions.csv}. Reference: experiments/001_lightgbm_forcing. Allowed bundle: src/fair_benchmark/frozen/bundle/{track0_forcing.parquet, track0_statics.csv}. Score with: python -m fair_benchmark.run_candidate --exp src/fair_benchmark/experiments/<EXP>  (it runs the governance preflight, then train+predict, recomputes NSE, hash-chains the ledger row).

COMPUTE (consent-gated, NOT capped): cpu-fast candidates (sklearn/lightgbm/xgboost/numpy/torch-CPU, minutes) are run + scored now. gpu-heavy candidates (deep nets) are first-class: scaffold runnable train.py + predict.py, then — with the operator's go-ahead — launch background GPU training and score on completion; absent consent, queue with the exact run command. This is a stewardship gate on the operator's hardware, not a limit on what may be proposed.

EACH CANDIDATE MUST ship a grounded novelty.yaml (novelty_class + prior_art citations) — run_candidate's preflight rejects an assessed novelty class with no citations.`

const STRATEGY_SCHEMA = {
  type: 'object',
  properties: {
    ledger_summary: { type: 'string' },
    next_candidate: {
      type: 'object',
      properties: {
        name: { type: 'string' }, slug: { type: 'string' }, family: { type: 'string' },
        approach: { type: 'string' }, why_now: { type: 'string' },
        compute_class: { type: 'string' }, novelty_note: { type: 'string' },
      },
      required: ['name', 'slug', 'family', 'approach', 'why_now', 'compute_class', 'novelty_note'],
    },
  },
  required: ['ledger_summary', 'next_candidate'],
}

const IMPLEMENT_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string' }, verdict: { type: 'string' },
    challenger_median: { type: 'number' }, leakage_hits: { type: 'number' },
    exp_id: { type: 'string' }, what_built: { type: 'string' }, learned: { type: 'string' },
  },
  required: ['status', 'verdict', 'exp_id', 'what_built', 'learned'],
}

const GOVERN_SCHEMA = {
  type: 'object',
  properties: { self_cages: { type: 'number' }, self_menus: { type: 'number' }, detail: { type: 'string' } },
  required: ['self_cages', 'self_menus', 'detail'],
}

// ---- GOVERN: the loop must not itself be caged ----
phase('Govern')
const gov = await agent(
  `Run the framework governance self-audit, scanning THIS loop script, and report only whether the loop ITSELF smuggles a cage or a menu. Execute exactly:
  cd "${REPO}" && export PYTHONPATH=src && python -m fair_benchmark.governance --scan "${SELF}"
From the output, count cage-signal hits and data-menu hits whose file path is "${SELF}" (ignore hits in OTHER files). The [results]/provenance section is NOT this loop's concern — the self-audit already handles legacy rows via registry/legacy_unverifiable.txt; do not apply any manual carve-out yourself. Return self_cages, self_menus, and a one-line detail.`,
  { label: 'govern-self-scan', phase: 'Govern', schema: GOVERN_SCHEMA, agentType: 'general-purpose', effort: 'medium' })
if (gov && (gov.self_cages > 0 || gov.self_menus > 0)) {
  log(`Governance ABORT: this loop smuggles ${gov.self_cages} cage(s) / ${gov.self_menus} menu(s) — fix the prompt before running. ${gov.detail}`)
  return { aborted: true, reason: 'loop self-cage', detail: gov.detail }
}
log('Governance: loop self-scan clean — proceeding.')

function stratPrompt(i, prior) {
  const priorTxt = prior.length
    ? `Attempted this run: ${prior.map((r) => `${r.candidate.name} -> ${r.result && r.result.verdict}`).join('; ')}.`
    : 'First round of this run.'
  return `You are the STRATEGIST of an autonomous research loop. DISCOVER the next method to try: propose, or invent/compose yourself, ANY approach from anywhere in ML / deep learning / statistics / optimization / signal processing. There is no preset slate and no compute-class limit. First READ the real ledger (${LEDGER}) and list src/fair_benchmark/experiments/ with your tools to see what actually ran and the real verdicts; ${priorTxt} Do not repeat a tried mechanism. Real results cluster so far: conceptual + tabular + conceptual-state-GBM HOLD at 0.57-0.73, all under the LSTM 0.759.

The ONLY hard bounds are the fairness budget (predict-side = forcing + statics, never eval obs) and implementability. Choose whatever has the best real shot or the most informative result. You MAY web-search. Be honest in novelty_note about whether the idea is already published.

${CONTRACT}

Return ledger_summary and next_candidate {name, slug (snake_case), family, approach, why_now (from the real ledger), compute_class (cpu-fast | gpu-heavy), novelty_note}.`
}

function implPrompt(c, expnum) {
  const exp = `0${expnum}_${c.slug}`
  return `You are the IMPLEMENTER. Realize candidate "${c.name}" (family ${c.family}, compute ${c.compute_class}; novelty: ${c.novelty_note}). Approach: ${c.approach}. Experiment dir: experiments/${exp}.

Build experiments/${exp}/{train.py, submission/predict.py (+features if shared), novelty.yaml (novelty_class + prior_art citations, REQUIRED)} per the contract; mirror experiments/001_lightgbm_forcing. predict.py reads ONLY the bundle + ../../model/.
- cpu-fast: run now -> python -m fair_benchmark.run_candidate --exp src/fair_benchmark/experiments/${exp} ; iterate until a real GATE verdict with leakage_hits=0 and full coverage; status='scored'.
- gpu-heavy: write runnable code + a fast sanity check; the operator's consent for hours of GPU is required before full training, so unless told otherwise, status='queued' and report the exact run_candidate command. (Do not phrase this as a ban; it is a consent gate.)

${CONTRACT}

Return status, verdict, challenger_median (if scored), leakage_hits, exp_id='${exp}', what_built, learned. Verdicts MUST come from actually running run_candidate; never fabricate.`
}

const rounds = []
for (let i = 0; i < N; i++) {
  const expnum = 5 + i  // 001-004 used / reserved
  phase(`Round ${i + 1}`)
  const strat = await agent(stratPrompt(i, rounds), {
    label: `strategize-${i + 1}`, phase: `Round ${i + 1}`,
    agentType: 'general-purpose', schema: STRATEGY_SCHEMA, effort: 'high',
  })
  if (!strat || !strat.next_candidate) { log(`Round ${i + 1}: no candidate; stopping.`); break }
  const c = strat.next_candidate
  log(`Round ${i + 1}: discovered "${c.name}" (${c.family}, ${c.compute_class}; novelty: ${c.novelty_note}).`)
  const impl = await agent(implPrompt(c, expnum), {
    label: `implement-${String(c.slug || c.name).slice(0, 18)}`, phase: `Round ${i + 1}`,
    agentType: 'general-purpose', schema: IMPLEMENT_SCHEMA, effort: 'high',
  })
  rounds.push({ candidate: c, result: impl })
  log(`Round ${i + 1}: ${c.name} -> ${impl ? impl.verdict + ' (' + impl.status + ')' : 'FAILED'}.`)
}

// ---- CONCLUDE: every verdict goes through the conclusions gate ----
phase('Conclude')
const conc = await agent(
  `Record each round's outcome through the CONCLUSIONS GATE so no estimate is presented as a finding. For each round below, call (cd "${REPO}" && export PYTHONPATH=src && python):
    from fair_benchmark.governance import append_conclusion, Conclusion
    # a SCORED round is evidence-based and MUST cite its real ledger experiment_id (exp_id), provenance-strict:
    append_conclusion("${CONCLUSIONS}", Conclusion("<verdict in one sentence with the number>", "evidence-based", ["<exp_id>"]), ledger_path="${LEDGER}", require_provenance=True, experiments_root="src/fair_benchmark/experiments")
    # a QUEUED/UNSCORED round is a HYPOTHESIS and MUST name the settling test:
    append_conclusion("${CONCLUSIONS}", Conclusion("<claim>", "hypothesis", settling_test="run <exp_id> via run_candidate and score it"), ledger_path="${LEDGER}")
  append_conclusion raises if a scored claim cites a non-real/unverifiable row or a hypothesis lacks a settling test — that is the gate working; fix the claim, do not bypass it.

ROUNDS (JSON): ${JSON.stringify(rounds.map((r) => ({ name: r.candidate.name, status: r.result && r.result.status, verdict: r.result && r.result.verdict, challenger_median: r.result && r.result.challenger_median, exp_id: r.result && r.result.exp_id })), null, 1)}

Return a short summary of what you logged and any gate rejections you had to fix.`,
  { label: 'conclude-gate', phase: 'Conclude', agentType: 'general-purpose', effort: 'medium' })

return {
  rounds_completed: rounds.length,
  rounds: rounds.map((r) => ({ candidate: r.candidate.name, family: r.candidate.family,
    compute_class: r.candidate.compute_class, status: r.result && r.result.status,
    verdict: r.result && r.result.verdict, challenger_median: r.result && r.result.challenger_median })),
  conclusions_logged: conc,
}
