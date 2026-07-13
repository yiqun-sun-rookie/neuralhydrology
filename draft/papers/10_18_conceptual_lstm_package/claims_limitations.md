# Claims and limitations

## Supported claims

- The package provides a protocol-audited CAMELS-US 531 conceptual benchmark relative to a reproduced LSTM reference.
- GR4J is the strongest conceptual model under the final PT 5k x 3 same-protocol headline.
- The LSTM ensemble is the strongest evaluated predictor in the current setup.
- Conceptual models can be used as structure-reference probes to decompose where the LSTM advantage concentrates.
- D05/D06 show that snow-dominated MAM high flow is the retained joint context with the highest concentration ratio.
- GR4J/XAJ external snow front ends are effective-equivalent under zero initial ice, as tested by `test/test_id10_pdd_fairness.py`.
- XAJ has 20 nominal parameters but 18 effective active parameters in the current zero-ice setup.
- HBV-lite snow handling is intrinsic HBV structure, not the shared external PDD wrapper.
- Saved GR4J/XAJ/HBV parameter artifacts replay under the current code for all 531 basins in both saved-state and warmup-recomputed modes.
- D01 static-attribute diagnostics support a correlational structure-regime claim; D02 selected-case hydrographs provide time-series illustrations of residual patterns; D03/D04 population residual diagnostics show that MAM/high-flow penalties and attribute links persist beyond selected cases; D05/D06 localize the LSTM advantage into season-flow contexts.

## Unsupported claims

- Do not claim a new predictive state of the art.
- Do not claim conceptual models are competitive with the LSTM ensemble overall.
- Do not claim conceptual models provide a deployable predictive complement to LSTM.
- Do not claim D05/D06 prove causal event mechanisms or LSTM process realism.
- Do not infer XAJ superiority over HBV from their median ordering alone; no equivalence or superiority test was specified.
- Do not present the PET-bug correction as a method gain.
- Do not mix 447-subset Kratzert reproduction numbers with full-531 headline rankings.
- Do not imply strict information equality between conceptual models and LSTM; the LSTM uses regional learning and static attributes.
- Do not describe all three conceptual models as sharing one identical snow module.
- Do not compare nominal parameter counts without also reporting effective active parameter counts.

## Boundary conditions

- Full-531 LSTM headline diagnostics remain NSE-based in the main benchmark, while D02-D06 use saved daily LSTM test predictions or generated D04 residual artifacts for post-hoc seasonal/high-flow and advantage-decomposition checks.
- Conceptual diagnostic metrics are valid for comparing GR4J/XAJ/HBV; LSTM residual checks are post-hoc diagnostics, not proof of LSTM process realism.
- GR4J and XAJ external PDD modules are controlled as effective-equivalent; HBV is included as a different conceptual school with an intrinsic degree-day snow routine.
- The stale PET-bug regime diagnostic is quarantined and must not be reused as manuscript evidence.
- Saved-parameter replay is an artifact-validity audit, not a fresh full CMA-ES recalibration.
