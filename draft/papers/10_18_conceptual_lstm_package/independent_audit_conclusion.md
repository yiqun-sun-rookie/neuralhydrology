# Independent audit feasibility conclusion

## Verdict

Core benchmark claims and manuscript claim boundaries are independently auditable from the registered snapshot. The committed clean checkout and one content-pinned local external archive rebuild it without a working-tree overlay.

## Evidence

- Stale-reference blockers: 0.
- Reproducibility status: committed clean-checkout reconstruction verified with one content-pinned local external archive; 14 top-level outputs matched across two consecutive builds.
- Main headline medians are regenerated from saved per-basin metric artifacts:
  - GR4J: 0.653287
  - XAJ: 0.619564
  - HBV: 0.617033
  - LSTM ensemble: 0.759225
- Four-model oracle median NSE is 0.761295; median gain over LSTM is 0.000000.
- PDD fairness is testable: GR4J/XAJ external snow front ends are effective-equivalent under zero initial ice, while XAJ ice parameters are inactive in this setup.
- Saved-parameter replay is testable: all GR4J/XAJ/HBV saved parameter artifacts replay under the current code for 531 basins in saved-state and warmup-recomputed modes.
- Parameter accounting is explicit: GR4J+PDD = 8 nominal/effective, XAJ+PDD = 20 nominal / 18 effective active, HBV-lite = 13 intrinsic parameters.
- Stale PET-bug diagnostics are classified as quarantined or historical, not as active manuscript evidence.
- Advantage-decomposition value is backed by D01 basin-attribute relationships, D02 selected-case seasonal residuals, D03 snow-population residuals, D04 full-population residual attribute checks, and D05/D06 concentration of the LSTM margin relative to the row-wise lowest-error conceptual comparator, with hydro signatures and daily residuals labeled as post-hoc diagnostics.
- Manuscript claim boundaries are captured in `key_points.md`, `manuscript_ready_claim_map.md`, `reviewer_risk_checklist.md`, and `final_submission_readiness_memo.md`.

## How to audit

Run:

```powershell
pytest test/test_id10_pdd_fairness.py -q
pytest test/test_id10_manuscript_evidence_package.py -q
python -X utf8 -m src.xaj_global_pilot.scripts.replay_conceptual_saved_params --out-dir draft/papers/10_18_conceptual_lstm_package/audit/R01_saved_parameter_replay_current_code
python -X utf8 -m src.lstm_fair_531.scripts.seasonal_residual_deep_dive --population snow --max-basins 0 --out-dir draft/papers/10_18_conceptual_lstm_package/deep_dive/D03_population_seasonal_residual_20260709
python -X utf8 -m src.lstm_fair_531.scripts.seasonal_residual_deep_dive --population all --max-basins 0 --out-dir draft/papers/10_18_conceptual_lstm_package/deep_dive/D04_full_population_seasonal_residual_20260709
python -X utf8 -m src.lstm_fair_531.scripts.population_residual_attribute_review --dive-dir draft/papers/10_18_conceptual_lstm_package/deep_dive/D04_full_population_seasonal_residual_20260709
python -X utf8 -m src.lstm_fair_531.scripts.lstm_advantage_decomposition
python -X utf8 -m src.lstm_fair_531.scripts.joint_advantage_decomposition
python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package
```

Then inspect:

- `MANIFEST.json`
- `tables/main_benchmark.csv`
- `tables/paired.csv`
- `tables/conceptual_diagnostics.csv`
- `tables/regime_summary.csv`
- `tables/parameter_accounting.csv`
- `tables/fairness_audit.csv`
- `audit/R01_saved_parameter_replay_current_code/saved_parameter_replay_summary.csv`
- `deep_dive/D01_structure_diagnostic_20260709/README.md`
- `deep_dive/D02_seasonal_residual_20260709/README.md`
- `deep_dive/D03_population_seasonal_residual_20260709/README.md`
- `deep_dive/D04_full_population_seasonal_residual_20260709/README.md`
- `deep_dive/D04_full_population_seasonal_residual_20260709/population_residual_attribute_review.md`
- `deep_dive/D05_lstm_advantage_decomposition_20260709/D05_lstm_advantage_decomposition_memo.md`
- `deep_dive/D06_joint_season_flow_advantage_20260709/D06_joint_season_flow_advantage_memo.md`
- `manuscript_ready_claim_map.md`
- `manuscript_sections.md`
- `key_points.md`
- `manuscript_full_draft.md`
- `figure_table_captions.md`
- `reviewer_risk_checklist.md`
- `final_submission_readiness_memo.md`
- `provenance_ledger.csv`
- `audit/stale_reference_audit.csv`

## Residual risk

The package contains a complete manuscript draft and a content-pinned registered snapshot. Final submission still requires venue formatting, a finalized bibliography, and publication of the registered external archive. Do not remove the snow-module distinction, nominal/effective parameter accounting, or strongest-evaluated-reference boundary from Methods/Limitations during manuscript polishing.
