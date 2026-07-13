# Figure and table captions

## Main Tables

Table 1. Full-531 benchmark summary. Basin-wise NSE medians and means for GR4J+PDD, XAJ+PDD, HBV-lite, a seed-100 LSTM, and the eight-seed LSTM ensemble under the same CAMELS-US reverse split and Maurer forcing. The table establishes the LSTM ensemble as the strongest evaluated predictor and GR4J as the strongest conceptual baseline.

Table 2. Paired LSTM-versus-conceptual comparisons. Per-basin paired differences, LSTM win rates, Wilcoxon tests, and bootstrap confidence intervals compare the eight-seed LSTM ensemble against each conceptual model on the common 531 basins.

Table 3. Conceptual diagnostic metrics. KGE, absolute bias, absolute peak bias, absolute low-flow bias, calibration-evaluation gap, and failure counts summarize how the three conceptual models trade overall efficiency against interpretable flow-signature behavior.

Table 4. Regime-wise benchmark summary. Median NSE values by hydrologic regime show how conceptual model rankings shift relative to the LSTM reference, especially in snow-dominated basins.

Table 5. Parameter accounting and snow-module status. Nominal and effective active parameter counts distinguish GR4J/XAJ external PDD front ends from the intrinsic HBV-lite snow routine.

Table 6. Fairness audit summary. Structure, calibration, stale-reference, and bounds checks classify each potential fairness issue as effective-equivalent, model-intrinsic, aligned, disclosed, or historical-only.

Table 7. Concentration of the LSTM advantage in three headline hydrologic contexts. Context share is compared with the share of the positive best-conceptual-minus-LSTM mean absolute error gap; their ratio measures concentration, and shared failure rate is the fraction of contexts in which GR4J, XAJ, and HBV all have higher mean absolute error than the LSTM.

## Figures

Figure 1. Empirical CDF of basin-wise NSE. The LSTM ensemble distribution lies to the right of all conceptual models, while GR4J is the strongest conceptual distribution.

Figure 2. Regime-wise median NSE. Median performance by hydrologic regime shows both the overall LSTM lead and regime-specific conceptual model shifts.

Figure 3. Conceptual-model diagnostic trade-offs. Median absolute bias, peak bias, low-flow bias, and calibration-evaluation gap show that different conceptual structures emphasize different error modes.

Figure 4. LSTM margin over the best conceptual model by regime. The distribution of LSTM ensemble NSE minus the best conceptual NSE shows that conceptual models occasionally win individual basins, but do not provide a median predictive complement to the LSTM.
