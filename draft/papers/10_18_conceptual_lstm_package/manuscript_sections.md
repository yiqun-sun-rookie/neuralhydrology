# Manuscript section draft pack

## Methods: benchmark design

We evaluated three conceptual rainfall-runoff model schools, GR4J, XAJ, and HBV-lite, on the CAMELS-US 531-basin benchmark using the repro_v01 reverse split. Conceptual models were calibrated on 1999-10-01 to 2008-09-30 and evaluated on 1989-10-01 to 1999-09-30 with Maurer forcing, Priestley-Taylor PET, and a one-year warmup before the evaluation period. Each conceptual model used the same CMA-ES budget of 5000 function evaluations per restart and three restarts, with the same normalized initial mean, step size, seed schedule, and NSE objective.

## Methods: structure and snow accounting

The benchmark preserves model-school differences while controlling external modules. GR4J+PDD and XAJ+PDD use external degree-day snow front ends whose active no-ice behavior is tested as effective-equivalent under the current zero-ice CAMELS-US setup. XAJ keeps a six-parameter PDD wrapper for historical compatibility, but the two ice parameters are inactive because ice storage starts at zero and no process creates ice storage. We therefore report XAJ as 20 nominal parameters and 18 effective active parameters. HBV-lite, in contrast, contains an intrinsic HBV degree-day snow routine with `SNOWPACK` and `MELTWATER` states; this is treated as part of the HBV model structure rather than as a shared external PDD module.

## Methods: LSTM reference and audit trail

The conceptual benchmark is compared with a reproduced LSTM reference rather than presented as a predictive state-of-the-art challenge. The LSTM uses the same 531 basins, Maurer forcing, and reverse split, but also uses regional learning with static attributes; it is the strongest evaluated predictive reference, not a strict same-information conceptual challenger. We include a seed-100 single model and an eight-seed ensemble. All headline tables and figures are regenerated from saved per-basin artifacts by `python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package`; the snow-front-end equivalence claim is checked by `pytest test/test_id10_pdd_fairness.py -q`.

## Results: predictive boundary

The conceptual-model median NSE values are 0.653287 for GR4J, 0.619564 for XAJ, and 0.617033 for HBV-lite. These descriptive medians do not establish superiority or equivalence between XAJ and HBV-lite. The LSTM single model reaches median NSE 0.733187, and the eight-seed LSTM ensemble reaches 0.759225. In paired comparison, the LSTM ensemble exceeds GR4J by median NSE 0.087287 and wins on 0.902 of common basins.

## Results: structure-reference diagnostics

Although the LSTM is the strongest evaluated predictor, the conceptual models expose different diagnostic behavior. GR4J has the best overall median NSE and KGE, with median KGE 0.686994 and the smallest median absolute bias (0.095179). HBV-lite has the smallest median absolute peak bias (0.164674) and has the lowest absolute peak bias among the three conceptual models in 247 basins. XAJ has the smallest median absolute low-flow bias (0.612464) and has the lowest absolute low-flow bias among the three in 255 basins. These trade-offs support the use of conceptual models as diagnostic baselines rather than as competitive predictors against the LSTM ensemble.

## Results: LSTM advantage decomposition

The key diagnostic result is not that the LSTM wins overall, but that its advantage is concentrated. Table 7 maps context share to positive best-gap share, concentration ratio, and shared failure rate. In D05, snow-dominated MAM contexts account for 7.2% of basin-season contexts but 18.6% of the positive LSTM-vs-best-conceptual MAE gap. Snow-dominated high-flow contexts account for 9.6% of basin-flow contexts but 36.1% of the positive gap. D06 combines season and flow group using the D04 daily residual archive: snow-dominated MAM high-flow contexts account for 2.8% of basin-season-flow contexts but 13.6% of the positive best-conceptual MAE gap, with concentration ratio 4.90 and shared failure rate 0.914. This supports the use of GR4J/XAJ/HBV as structure-reference probes for locating the LSTM advantage, not as predictive complements.

## Results: regime heterogeneity and oracle check

The relative behavior of the three conceptual structures varies by hydrologic regime, while the LSTM remains the strongest predictor. In snow-dominated basins, XAJ and HBV-lite have higher median NSE (0.646338 and 0.650072) than GR4J (0.630799), while the LSTM ensemble remains higher at 0.796547. Across all basins, a four-model oracle reaches median NSE 0.761295, with median gain 0.000000 over the LSTM ensemble. This indicates that conceptual models provide useful diagnostic contrasts, but the evidence does not support a predictive-complement claim.

## Limitations

This benchmark should not be read as strict information equality between conceptual models and the LSTM: the LSTM uses regional learning and static attributes, while conceptual models are calibrated per basin. Full-population LSTM headline diagnostics remain NSE-based in the main benchmark, while D02-D06 use saved daily LSTM test predictions or generated residual artifacts as post-hoc diagnostics. D05/D06 localize rows where all three conceptual models have higher error, but do not prove causal event mechanisms or LSTM process realism. HBV-lite's snow routine is intrinsic to the model and should not be described as the same external PDD module used by GR4J and XAJ. Finally, the current paper package is auditable from saved artifacts and tests, but a full recalibration of all conceptual models is computationally more expensive than the manuscript evidence rebuild.
