# Framework principles — the four evidence firewalls

A real research episode exposed how an LLM-driven auto-research framework fails by
default: the cheapest output (confident prose / estimates) masquerades as the
expensive output (real findings), and wherever the orchestrator writes a prompt it
smuggles in human priors disguised as the system's own choices. The root cause:
**no firewall between generation (cheap, confident, unbounded LLM talk) and
validation (expensive, real, measured).**

The rule, one sentence: **generate freely — but nothing becomes a RESULT, an
AUTONOMOUS CHOICE, a NOVELTY claim, or a CONCLUSION without a grounded check the
orchestrator did not author.** The four firewalls below give that rule teeth in
code (`governance.py`, tested in `tests/test_governance.py`; self-audit via
`python -m fair_benchmark.governance`).

## 1. Results firewall — only real runs count
A reported number must trace to an append-only ledger row with a predictions hash;
estimates are never results.
- Teeth: `is_real_result`, `verify_number` (a claimed number must match a ledger
  row; a claim with no run fails), `verify_provenance` (re-hash the predictions
  file vs the ledger sha — a logged number cannot be silently swapped).
- The only writer of a result is `run_candidate` → `score.score_submission` after a
  real predict+score. The ledger (`registry/portfolio_ledger.csv`) is the single
  source of truth for "what is real".

## 2. Autonomy firewall — declared constraints, no smuggled cages
Every constraint on the search is declared in `constraints.yaml` and classified as
an **invariant** (fairness/physical/stewardship necessity) or a **cage**
(orchestrator convenience). A healthy framework has **zero active cages**; the
system may propose or invent anything the invariants allow.
- Teeth: `load_constraints` / `active_cages` (must be empty), and
  `scan_orchestration_for_cages` — a heuristic linter that flags search-narrowing
  language (menus, compute caps, "do not run") creeping into orchestration prompts.
- Removed cages are kept as tombstones in `constraints.yaml` so re-introduction is
  visible: `cpu_only_search`, `seeded_technique_menu`, `gpu_execution_blocked`.
- Compute is an execution boundary, not a research cage. Heavy GPU runs are
  first-class; the only gate is `operator_consent_for_heavy_compute` (an invariant:
  stewardship of the operator's hardware/time, not a limit on what may be proposed).

## 3. Novelty firewall — grounded against literature, never self-asserted
A candidate's novelty is established against external prior art, not by the
proposer's say-so.
- Teeth: `validate_novelty` — any assessed novelty class (`reproduction`,
  `incremental`, `new-to-hydrology`, `genuinely-novel`) requires non-empty
  `prior_art` citations (what was it checked against?). "Novel" without a literature
  check is invalid. (This is why a published method — e.g. differentiable HBV / dPL
  — cannot be recorded as a "discovery".)

## 4. Conclusions firewall — falsifiable, ledger-cited
A consequential claim is either **evidence-based** (cites real ledger rows) or a
**hypothesis** (names the runnable test that would settle it). A hypothesis may not
be presented as a conclusion.
- Teeth: `validate_conclusion` / `append_conclusion` (refuses to log an
  evidence-based claim whose cited experiments are not real ledger results, and a
  hypothesis with no settling test). Strategic conclusions go to
  `registry/conclusions.md` through this gate.

## Wiring: the firewalls run in the live path, not on request

The teeth are useless as an offline library. They are wired in:
- **`run_candidate` preflight** (`governance_preflight`): before any candidate is
  scored, it refuses on an active cage and validates the candidate's `novelty.yaml`
  (autonomy + novelty). Every candidate passes through here.
- **Tamper-evident ledger**: `ledger.append_attempt` (called only by `score`) writes
  the hash-chain; a hand-appended/edited row breaks it and `verify_chain` flags it.
  `run_candidate` also writes a committed `submission/predictions.sha256` sidecar so
  the recorded sha survives even when the large predictions file is git-ignored.
- **Governed-loop contract** (`workflows/governed_autoresearch_loop.js`): any
  autonomous loop MUST (a) self-scan its own prompt for cages/menus before running
  and abort if caged, (b) score only through `run_candidate`, and (c) route every
  round verdict through `append_conclusion` (scored → evidence-based citing a real
  ledger row; unscored/estimate → hypothesis with a settling test). A loop that
  emits a ranking/verdict without these gate calls is non-compliant.
- **Enforcing self-audit**: `python -m fair_benchmark.governance --scan <prompts>`
  exits non-zero on active cages, cage/menu hits, ledger chain breaks, or PASS/HOLD
  rows that are not provenance-verifiable. Run it as a pre-flight and in CI — pass
  the actual orchestration prompts via `--scan` (a clean committed-code scan alone
  is NOT an all-clear).

## The fundamental limit (why local checks are necessary but not sufficient)
The threat is our own agents/hands taking shortcuts, not a cryptographic attacker.
These firewalls make lazy/accidental cheating break loudly. They **cannot** stop a
**deliberate in-environment agent**: the hash-chain is keyless (an agent can rerun
`row_hash` and drop a matching predictions file), and any local artifact an agent can
write, it can forge. The real last line of defense is a **trusted verifier outside the
agent's reach** — the human judge + an independent audit from a clean context (which
is precisely what caught these residuals across audit rounds), or an out-of-environment
re-execution of the candidate. Treat the local firewalls as bar-raisers and
honesty-keepers for that verifier, never as a substitute for it.

## Known remaining gaps (honest, prioritized)
- **Novelty citations not resolved** against an external index (DOI/Crossref): a
  fabricated citation still passes `validate_novelty`. Fix: resolve cites + a separate
  vetting agent.
- **No compute/identity accounting** in the ledger (a scaled clone of the baseline
  could "win"). Fix: record compute/seed/param/family per row + iso-compute at the gate.
- `train.py` eval-leakage is **surfaced heuristically** (`scan_train_for_eval_leakage`,
  reported by the preflight) but not hard-blocked or sandboxed; a paraphrased leak can
  still pass. Fix: eval-period-aware sandbox for `train.py`.
- The **old ad-hoc loop scripts** (open-loop, discovery, novelty-rerank) predate the
  governance wiring and still trip the scanner; the **canonical governed loop**
  (`workflows/governed_autoresearch_loop.js`) supersedes them.
- Legacy pre-retention rows (`gr4j_pdd_FINAL_full531`, `002_b`) are listed in
  `registry/legacy_unverifiable.txt` and downgraded to an acknowledged WARN so the
  gate is green on a clean state; any NEW unverifiable row still hard-FAILs.

---
Why this is the deliverable, not a candidate or a GPU run: the episode's lesson is
that the framework's *integrity*, not any single experiment, is what was broken.
These firewalls are the framework's immune system — the checks a human reviewer had
been performing manually (catching claimed-vs-real, autonomous-vs-steered,
novel-vs-published, concluded-vs-estimated), now encoded so they run every time.
