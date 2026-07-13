# Manuscript skeleton and claim map

## Working title

Locating Where Long Short-Term Memory Networks Win: Three Conceptual Rainfall-Runoff Models as Structural References Across 531 United States Basins

## One-sentence contribution

Aggregate scores hide how a predictive margin is distributed; three audited conceptual structures locate where the LSTM advantage concentrates across hydrological regime, season, and flow context.

## Abstract skeleton

Aggregate rainfall-runoff performance scores rank models but do not show whether a predictive advantage is diffuse or concentrated in particular hydrological contexts. We quantify that distribution across 531 CAMELS-US basins using GR4J, XAJ, and HBV as structural references to a reproduced eight-seed LSTM ensemble. The LSTM uses regional learning and 27 static basin attributes, so the comparison is diagnostic rather than a same-information prediction contest; the conceptual structures are not predictive competitors. Its median NSE is 0.759225, compared with 0.653287 for the strongest single conceptual model, GR4J. Snow-dominated MAM contexts represent 7.2% of basin-season rows but 18.6% of the positive gap relative to the lowest-error conceptual model in each row; snow-dominated high-flow contexts represent 9.6% of basin-flow rows but 36.1% of that gap. Across all 531 basins, snow fraction is positively associated with the LSTM margin over the basin-wise conceptual comparator with the highest NSE (rho = 0.429, q = 1.65e-23). Snow-dominated MAM high flow is the retained joint context with the highest concentration ratio: 2.8% of joint rows account for 13.6% of the positive gap, and all three evaluated conceptual models have higher mean absolute error in 91.4% of those rows. The result is a post-hoc diagnosis of where the known ranking accumulates, not evidence of causal mechanism, process realism, or deployable predictive complementarity.

## Results narrative

Boundary. The LSTM ensemble is the strongest evaluated predictive reference: median NSE 0.759225, compared with GR4J at 0.653287, XAJ at 0.619564, and HBV at 0.617033. A four-model oracle reaches median NSE 0.761295 with median gain 0.000000 over the LSTM ensemble, so this is not a predictive-complement paper.

1. LSTM advantage is not uniform: snow-dominated MAM contexts account for 7.2% of basin-season contexts but 18.6% of the positive gap relative to the lowest-error conceptual model in each row; snow-dominated high-flow contexts account for 9.6% of basin-flow contexts but 36.1% of the positive gap.
2. Across all 531 basins, snow fraction is positively associated with the LSTM margin over the basin-wise conceptual comparator with the highest NSE (rho = 0.429, q = 1.65e-23), supporting a population-level rather than selected-case pattern.
3. Snow-dominated MAM high flow is the retained joint context with the highest concentration ratio: 2.8% of basin-season-flow contexts account for 13.6% of the positive row-wise gap, with concentration ratio 4.90; all three conceptual models have higher MAE in 0.914 of rows.

## Claims that are supported

- The ID10/ID18 package provides a protocol-audited conceptual benchmark relative to a reproduced LSTM reference.
- GR4J is the strongest single conceptual model under the final 5k x 3 PT same-protocol headline.
- The LSTM ensemble is the strongest evaluated predictor in this setup.
- LSTM advantage is concentrated rather than uniform, especially in snow-dominated MAM and high-flow contexts.
- Agreement across GR4J/XAJ/HBV errors can be used to locate the LSTM margin relative to the lowest-error conceptual comparator in each row.
- D06 identifies snow-dominated MAM high-flow as the strongest current joint advantage concentration zone.
- GR4J/XAJ external PDD snow handling is effective-equivalent under the current zero-ice CAMELS-US setup; XAJ should be reported as 20 nominal and 18 effective active parameters.
- The saved conceptual parameter artifacts replay under the current code across all 531 basins; this supports artifact continuity after fairness-related code cleanup.
- D01-D06 deep dives make the diagnostic decomposition concrete: static snow/topography/aridity attributes align with model-structure disagreements, D03/D04 show population residual penalties, and D05/D06 show that a small snow-dominated MAM high-flow context overcontributes to the LSTM advantage.

## Claims that are not supported

- Do not claim a new predictive state of the art.
- Do not claim conceptual models are competitive with the LSTM ensemble overall.
- Do not claim conceptual models complement LSTM prediction deployably.
- Do not claim causal event attribution or LSTM process realism from D05/D06.
- Do not infer XAJ superiority over HBV from their median ordering alone; no equivalence or superiority test was specified.
- Do not claim PET-bug correction is a method gain.
- Do not mix 447-subset Kratzert reproduction numbers with full-531 headline rankings.
- Do not imply strict information equality: the LSTM uses regional learning and static attributes.
- Do not describe HBV as using the same external PDD front end; its snow routine is intrinsic HBV structure.

## Submission readiness

The core benchmark and decomposition claims are auditable from the registered snapshot. Nineteen external evidence inputs are pinned by byte size and SHA-256 digest and packaged in a single content-pinned local external archive. The committed clean checkout rebuilds the package after that archive is extracted. The committed clean checkout has been verified by rebuilding all 14 top-level outputs twice with zero digest differences. Old PET-bug diagnostics are quarantined and must not be reused as manuscript evidence. Submission still requires venue formatting, a finalized bibliography, and publication of the registered external archive.
