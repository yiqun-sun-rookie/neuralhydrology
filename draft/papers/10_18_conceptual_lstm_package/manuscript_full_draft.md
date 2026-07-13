# Locating Where Long Short-Term Memory Networks Win: Three Conceptual Rainfall-Runoff Models as Structural References Across 531 United States Basins

## Abstract

Aggregate rainfall-runoff performance scores rank models but do not show whether a predictive advantage is diffuse or concentrated in particular hydrological contexts. We quantify that distribution across 531 basins from the Catchment Attributes and Meteorology for Large-sample Studies data set for the contiguous United States (CAMELS-US), using three conceptual rainfall-runoff structures—GR4J, the Xinanjiang model, and an HBV-lite implementation—as references to a reproduced eight-seed long short-term memory (LSTM) network ensemble. Because the ensemble uses regional learning and 27 static basin attributes while the conceptual models are calibrated per basin, this is a diagnostic comparison rather than a strict same-information contest. The ensemble reached a median Nash-Sutcliffe efficiency (NSE) of 0.759225, compared with 0.653287 for the strongest single conceptual model, GR4J. We decomposed the positive gap between the LSTM and the conceptual model with the lowest mean absolute error in each basin-context row across hydrological regime, season, and flow group. Snow-dominated spring contexts represented 7.2% of basin-season contexts but 18.6% of the positive gap, while snow-dominated high-flow contexts represented 9.6% of basin-flow contexts but 36.1% of that gap. Across all 531 basins, snow fraction was positively associated with the LSTM margin over the basin-wise conceptual comparator with the highest NSE (rho = 0.429, q = 1.65e-23). The retained joint context with the highest concentration ratio was snow-dominated spring high flow: 2.8% of joint rows accounted for 13.6% of the positive gap, with a concentration ratio of 4.90; all three conceptual models had higher mean absolute error than the LSTM in 91.4% of those rows. Thus, three distinct conceptual structures convert a known overall ranking into a bounded diagnosis of where the predictive margin accumulates. The analysis remains post-hoc and associational; it does not identify causal event mechanisms or establish that the LSTM represents physical processes faithfully.

<!-- Abstract evidence: tables/main_benchmark.csv; tables/lstm_advantage_concentration.csv; deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv; deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv; deep_dive/D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv; deep_dive/D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv; deep_dive/D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv; deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv -->

**Keywords:** large-sample hydrology; rainfall-runoff modelling; long short-term memory network; conceptual model; diagnostic benchmark; error decomposition; snow-dominated basins

## 1. Introduction

Aggregate performance summaries are necessary for ranking rainfall-runoff models across heterogeneous basins, but they collapse the distribution of predictive differences into a small set of scores. A higher overall score does not reveal whether the margin is broadly distributed or disproportionately associated with particular basin regimes, seasons, or flow conditions. Distinguishing these possibilities is the scientific problem addressed here: it identifies the hydrological contexts that account for a known predictive gap without treating the gap itself as the novelty.

The CAMELS-US data set provides hydroclimatic forcing, streamflow records, and basin attributes for comparative analyses across a geographically diverse basin population (Addor et al. (2017)). Regional long short-term memory networks can learn shared relationships across basins while conditioning predictions on static attributes, and Kratzert et al. (2019) showed that this strategy can outperform established hydrological benchmarks across 531 CAMELS-US basins. Direct comparisons with conceptual benchmarks have also documented spatial and seasonal heterogeneity associated with snow and aridity (Lees et al. (2021)). Event-oriented work has further developed diagnostics that separate error dimensions across hydrological event types (Wang et al. (2026)). Overall predictive dominance, spatial heterogeneity, and event diagnostics are therefore established starting points rather than sufficient contributions for the present study.

Conceptual rainfall-runoff models remain useful for this narrower problem because their computations are constrained by explicit storage and flux arrangements. Knoben et al. (2019) provided a standardized modular framework for comparing conceptual structures and examining structural uncertainty. For the present diagnostic question, however, one conceptual benchmark would not distinguish a weakness specific to one formulation from an error pattern shared by several structures. We therefore use GR4J, Xinanjiang, and HBV-lite together as structural references: agreement among their errors identifies contexts in which all three fall behind the LSTM, while disagreement preserves information about structure-specific behaviour. They are not proposed as replacements, ensemble members, or deployable corrections for the LSTM.

The study makes one central contribution and uses two evidence layers to support it. The central contribution is a diagnostic decomposition of the positive mean absolute error difference between the LSTM and the conceptual comparator with the lowest mean absolute error in each basin-context row across hydrological regime, season, and flow group. The first evidence layer is population-level support: basin-wide attribute and residual analyses assess whether the snow, spring, and high-flow signal extends beyond selected examples. The second is joint context refinement: season and flow group are combined to identify the retained context with the highest concentration ratio. These layers are not separate methodological innovations; they test and sharpen the same claim that the known predictive advantage is hydrologically concentrated.

Three boundaries follow from this framing. First, the LSTM uses regional training and static attributes, whereas each conceptual model is calibrated per basin, so the study does not claim strict information equality. Second, the decomposition uses saved evaluation-period predictions after model development; it is a diagnostic analysis rather than an independently selected predictive model. Third, observed associations with snow fraction and season do not determine event type or causal mechanism. The aim is to locate an empirical error concentration, not to infer rain-on-snow events, snowmelt causality, or internal LSTM process realism.

## 2. Methods

### 2.1 Basin sample, forcing, and temporal split

The analysis used the same 531 CAMELS-US basins for all headline model summaries. Meteorological inputs were taken from the Maurer forcing product. Conceptual-model calibration and LSTM training used 1 October 1999 through 30 September 2008, and evaluation used 1 October 1989 through 30 September 1999. The conceptual simulations used a one-year warm-up before the evaluation period. This reverse temporal split matches the benchmark configuration recorded in `tables/protocol.csv` and preserves a common forcing product, basin population, and evaluation interval across the headline comparison.

Observed discharge was used as the prediction target and for evaluation, not as an input channel. The main score was basin-wise Nash-Sutcliffe efficiency, summarized by the median and mean across 531 basins. NSE is sensitive to squared errors and high flows, so the context decomposition additionally used mean absolute error (MAE) calculated from saved daily predictions. The MAE decomposition avoids relying on unstable low-flow NSE values when samples within a context are small.

### 2.2 Conceptual structural references

GR4J, Xinanjiang, and HBV-lite represent three different conceptual rainfall-runoff model families. GR4J combines four rainfall-runoff parameters with an external positive degree-day snow front end. Xinanjiang uses its characteristic tension-water and runoff-generation structure with an external degree-day snow front end. HBV-lite includes an intrinsic degree-day snow routine and internal snow states as part of its model structure. The three models therefore do not share an identical snow module, and that difference is retained as a structural feature rather than hidden by the comparison.

The conceptual models were calibrated separately for each basin with the Covariance Matrix Adaptation Evolution Strategy. Each restart used 5,000 objective evaluations, and three restarts were performed with an aligned normalized initialization and seed schedule. The calibration objective was NSE. Parameter accounting distinguished nominal parameters from parameters that were active in the evaluated zero-ice configuration. GR4J plus its snow front end had 8 nominal and 8 effective active parameters. Xinanjiang plus its historical six-parameter snow wrapper had 20 nominal parameters, but 18 were active because the two ice parameters did not affect the tested zero-ice path. HBV-lite had 13 intrinsic parameters. The finite zero-ice sequence tests support agreement of the GR4J and Xinanjiang external snow paths under the tested conditions; they do not establish universal structural identity.

The fixed model equations, state updates, and numerical implementations are traceable to `src/xaj_global_pilot/gr4j_core.py`, `src/xaj_global_pilot/xaj_model.py`, and `src/scl_hydro/hbv_lite_numpy.py`. Calibration bounds and their named presets are recorded in `src/xaj_global_pilot/bounds_presets.py`; the exact parameter counts and common protocol used here are exported in `tables/parameter_accounting.csv` and `tables/protocol.csv`. These references define the evaluated implementations and bounds without implying that they exhaust other valid formulations of the three model families.

### 2.3 LSTM reference and comparison boundary

The neural reference consisted of a single seed-100 model and an ensemble of eight LSTM models trained with seeds 100 through 800 for 30 epochs. The regional LSTM used five daily dynamic inputs—precipitation, minimum temperature, maximum temperature, short-wave radiation, and vapour pressure—from the Maurer product, together with 27 static basin attributes. Every run used a sequence length of 270 days, 256 hidden units, a batch size of 256, output dropout of 0.4, the Adam optimizer, and Nash-Sutcliffe-efficiency loss. The learning rate was 0.001 initially, 0.0005 from epoch 11, and 0.0001 from epoch 21. The fixed settings and complete attribute list are recorded in `results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/config.yml`, with the corresponding seed-specific configurations stored beside the other seven runs; the network implementation is `neuralhydrology/modelzoo/cudalstm.py`.

For each basin and date, ensemble discharge was the arithmetic mean of the eight daily predictions. The LSTM shared the headline basin set, forcing product, training interval, and evaluation interval with the conceptual comparison, but its regional learning and static inputs provide predictive information that per-basin conceptual calibration does not use in the same form.

For that reason, the LSTM is treated as the strongest evaluated predictive reference. The experiment asks how three conceptual structures behave relative to that reference, not which model wins under identical information. The overall LSTM ranking establishes the boundary of the analysis. It is neither claimed as a new state of the art nor counted as the paper's central contribution.

### 2.4 Headline performance and paired comparisons

For each model, basin-wise NSE values were collected in `tables/main_benchmark.csv`. The strongest single conceptual model means the fixed model family with the highest median basin-wise NSE; under this protocol, that model was GR4J. For basin-level margin analyses, the basin-wise conceptual comparator with the highest Nash-Sutcliffe efficiency was selected separately within each basin. Paired LSTM-versus-conceptual differences were taken from `tables/paired.csv`, which records the number of common basins, median paired difference, LSTM win rate, Wilcoxon signed-rank probability, and bootstrap confidence interval. A four-model oracle was also calculated by selecting, separately for each basin, the highest NSE among the LSTM ensemble and the three conceptual models. The oracle was used only as a diagnostic upper bound. It was not used to select or tune a deployable hybrid.

### 2.5 Advantage concentration metrics

The diagnostic analysis was performed on basin-context rows. A context was defined at three levels: hydrological regime by season, hydrological regime by flow group, and hydrological regime by season and flow group jointly. The saved regime labels followed fixed benchmark rules. A basin was snow-dominated when its snow fraction was at least 0.20, or when its coldest-quarter temperature was below 0 degrees Celsius and its cold-season precipitation fraction was at least 0.20. Among the remaining basins, humid meant an aridity index below 1.0, semi-humid meant an aridity index from 1.0 to below 1.5, and semi-arid/arid meant an aridity index of at least 1.5. The thresholds and classification code are recorded in `src/xaj_global_pilot/config.py` and `src/xaj_global_pilot/archive_legacy/classification.py`.

Spring was defined as March through May and is denoted MAM in the saved result tables. Daily flows were divided separately for each basin using the 10th and 90th percentiles of that basin's observed evaluation-period discharge: low flow was at or below the 10th percentile, high flow was at or above the 90th percentile, and middle flow lay between them. Each basin-model joint season-flow context was retained only when it contained at least 10 valid days. These definitions are implemented in `src/lstm_fair_531/scripts/seasonal_residual_deep_dive.py` and `src/lstm_fair_531/scripts/joint_advantage_decomposition.py`.

For each basin-context row, the conceptual comparator with the lowest mean absolute error in each row was selected from GR4J, Xinanjiang, and HBV-lite. The row-wise gap was this minimum conceptual MAE minus LSTM MAE. A positive value therefore indicates that even the lowest-error conceptual model was worse than the LSTM. Four quantities summarize each grouped context. `context_share` is the fraction of all valid basin-context rows belonging to the group. `positive_best_gap_share` is the group's share of the sum of positive row-wise gaps. `concentration_ratio` divides positive-gap share by context share; values greater than one indicate disproportionate contribution to the positive LSTM advantage. `shared_failure_rate` is the fraction of rows in which all three conceptual models had higher MAE than the LSTM. Share denominators were calculated separately within each context family—regime-season, regime-flow, and regime-season-flow—and were never pooled across those families.

These metrics describe concentration within saved evaluation-period predictions. They do not constitute an additional model, a validation-selected decision rule, or an event attribution procedure. Missing context metrics were excluded according to the decomposition scripts, while MAE contexts were retained when context-specific NSE was unavailable.

### 2.6 Population-level support and joint context refinement

The population-level support analysis linked basin-wide and context-specific residual targets to static basin attributes. The primary snow variable was the long-term snow fraction recorded in the static CAMELS-US attribute panel. Spearman rank correlations were used because the relationships need not be linear. Multiple comparisons were summarized with Benjamini-Hochberg false-discovery-rate-adjusted q values. The basin-wide table formed one correction family over all reported target-attribute pairs. The seasonal and flow analyses each formed a separate correction family over all context-target-attribute rows in its generated table. Primary claims use static attributes; streamflow-derived hydrological signatures were treated as supplemental diagnostics and were not used as inputs to a challenger model.

Selected hydrographs were retained only as time-series illustrations. The population analysis used all 531 basins with available conceptual and LSTM scores. The joint context refinement then combined regime, season, and flow group using the saved full-population daily residual archive. This sequence separates illustration, population support, and joint localization without treating any layer as causal evidence.

### 2.7 Audit trail and reproducibility classification

All headline tables, compact context summaries, claim maps, and manuscript drafts are generated by `python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package`. The evidence ledger maps each manuscript element to saved source artifacts and a regeneration command. Saved-parameter replay checks confirm continuity of the conceptual outputs under the current code without being described as a new calibration.

The registered snapshot is rebuildable from a committed clean checkout, 19 external evidence inputs pinned by byte size and SHA-256 digest and packaged in a single content-pinned local external archive, and one build command. The committed clean checkout has been verified by rebuilding all 14 top-level outputs twice with zero digest differences. A zero count of stale-reference blockers means only that known obsolete result references are quarantined or historical; it does not certify submission readiness.

## 3. Results

### 3.1 Predictive boundary

The eight-seed LSTM ensemble was the strongest predictor in the headline comparison (Table 1). Its median NSE was 0.759225, compared with 0.653287 for GR4J, 0.619564 for Xinanjiang, and 0.617033 for HBV-lite. The single LSTM model reached 0.733187. Relative to GR4J, the ensemble median paired difference was 0.087287, and the LSTM had higher NSE in 90.2% of the 531 common basins. The corresponding win rates against Xinanjiang and HBV-lite were 94.0% and 94.5%.

**Table 1. Headline basin-wise NSE summary.**

| Model | Basins | Median NSE | Mean NSE |
| --- | ---: | ---: | ---: |
| GR4J | 531 | 0.653287 | 0.610167 |
| Xinanjiang | 531 | 0.619564 | 0.574778 |
| HBV-lite | 531 | 0.617033 | 0.580150 |
| LSTM, seed 100 | 531 | 0.733187 | 0.698996 |
| LSTM, eight-seed ensemble | 531 | 0.759225 | 0.723702 |

The ranking fixes the interpretation used below: GR4J, Xinanjiang, and HBV-lite are not predictive competitors to the ensemble in this experiment. Their subsequent role is to supply explicit structural contrasts through which the distribution of the LSTM advantage can be examined.

<!-- Evidence: tables/main_benchmark.csv; tables/paired.csv -->

### 3.2 Structural contrasts below the LSTM reference

The conceptual models differed in their error signatures even though all three remained below the LSTM in overall NSE. GR4J had the highest conceptual median NSE and a median Kling-Gupta efficiency of 0.686994. Its median absolute bias was 0.095179. HBV-lite had the smallest median absolute peak bias, 0.164674, whereas Xinanjiang had the smallest median absolute low-flow bias, 0.612464. These contrasts show that the three structures emphasize different error modes; they do not reverse the headline predictive ranking.

Regime summaries also changed the ordering within the conceptual group. In snow-dominated basins, Xinanjiang and HBV-lite reached median NSE values of 0.646338 and 0.650072, respectively, compared with 0.630799 for GR4J. The LSTM ensemble remained higher at 0.796547. The regime result motivates using multiple conceptual references rather than interpreting a single conceptual model as representative of all explicit hydrological structures.

<!-- Evidence: tables/conceptual_diagnostics.csv; tables/conceptual_winners.csv; tables/regime_summary.csv -->

### 3.3 Concentration of the LSTM advantage

The positive LSTM advantage was not distributed in proportion to context frequency (Table 7). Snow-dominated spring contexts had a context share of 0.071563 but accounted for 0.185779 of the total positive row-wise gap. Their concentration ratio was 2.596016, and all three conceptual references had higher MAE than the LSTM in 0.940789 of those rows.

The concentration was stronger for snow-dominated high-flow contexts. They represented 0.095537 of basin-flow rows but accounted for 0.361229 of the positive row-wise gap, for a concentration ratio of 3.781018. Their shared failure rate was 0.953947. Thus, a context covering less than one tenth of basin-flow rows contributed more than one third of the accumulated positive LSTM advantage relative to the lowest-mean-absolute-error conceptual comparator in each row.

**Table 7. Concentration of the positive LSTM advantage in three headline contexts.**

| Context | Context share | Positive row-wise gap share | Concentration ratio | Shared failure rate |
| --- | ---: | ---: | ---: | ---: |
| Snow-dominated / spring | 0.071563 | 0.185779 | 2.596016 | 0.940789 |
| Snow-dominated / high flow | 0.095537 | 0.361229 | 3.781018 | 0.953947 |
| Snow-dominated / spring / high flow | 0.027763 | 0.136150 | 4.904101 | 0.914474 |

Table numbering follows the complete evidence package: Tables 2 through 6 contain the paired comparison, conceptual diagnostics, regime summary, parameter accounting, and fairness audit and are supplied as separately generated supporting tables. Table 7 is a compact view of the saved season, flow-group, and joint decomposition tables. It does not introduce a separate selection result. Its purpose is to show context prevalence, contribution to the positive gap, concentration, and agreement among the three conceptual failures side by side; each share is interpreted only within its context family.

<!-- Evidence: tables/lstm_advantage_concentration.csv; deep_dive/D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv; deep_dive/D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv; deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv -->

### 3.4 Population-level support

The concentration signal was also visible in basin-wide attribute relationships. Across all 531 basins, snow fraction was positively associated with the LSTM margin over the basin-wise conceptual comparator with the highest NSE (Spearman rho = 0.429, q = 1.65e-23). The result indicates that larger LSTM margins tended to occur in basins with a larger long-term snow fraction. It does not state that snow fraction alone determines model performance.

Context-specific residual relationships pointed in the same direction. For spring, the row-wise lowest-conceptual-MAE-minus-LSTM gap was positively associated with snow fraction (rho = 0.512, q = 9.07e-36). For high-flow rows, the corresponding association was rho = 0.510, q = 1.82e-35. This population-level support reduces reliance on selected hydrographs: the direction of the snow signal appears across the full basin panel and in both spring and high-flow residual summaries.

<!-- Evidence: deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv; deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv; deep_dive/D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv -->

### 3.5 Joint context refinement

Combining regime, season, and flow group identified snow-dominated spring high flow as the retained joint context with the highest concentration ratio. This group had a context share of 0.027763 and a positive row-wise gap share of 0.136150. The concentration ratio was 4.904101, and the shared failure rate was 0.914474. In counts, all three conceptual models had higher MAE than the LSTM in 139 of 152 valid rows.

This joint context refinement sharpens the empirical location of the advantage without assigning an event mechanism. The group is defined by basin regime, calendar season, and flow quantile, not by observed labels for snowmelt, rainfall-on-snow, or other event types. The result is therefore a localized shared-failure pattern among the three evaluated conceptual models.

<!-- Evidence: deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv; deep_dive/D06_joint_season_flow_advantage_20260709/tables/top_joint_advantage_contexts.csv -->

### 3.6 Oracle diagnostic

The four-model oracle reached a median NSE of 0.761295, compared with 0.759225 for the LSTM ensemble. The median oracle gain over the LSTM was 0.000000. A conceptual model had the highest basin-wise NSE in 73 basins, but the median oracle result provides no evidence for a general deployable predictive complement. The oracle is descriptive because it uses evaluation-period outcomes to select the best model separately for each basin.

<!-- Evidence: tables/oracle.csv -->

## 4. Discussion

### 4.1 One contribution with two evidence layers

Sections 3.3 through 3.5 form one argument at increasing resolution. The concentration analysis first shows that snow-dominated spring and high-flow contexts contribute more to the positive row-wise gap than their prevalence would imply. The population analysis then shows that the snow-linked margin extends across the basin sample rather than depending on selected hydrographs. Finally, the joint analysis localizes the retained combination of regime, season, and flow group with the highest concentration ratio.

These steps support one diagnostic contribution: several audited conceptual structures quantify where the established LSTM advantage accumulates. Selecting the lowest-mean-absolute-error conceptual comparator in each row prevents one weak structure from defining the comparison, while shared failure measures agreement across all three references. Population-level support and joint context refinement strengthen that claim without becoming separate predictive methods or changing the test-period ranking.

### 4.2 Interpretation of the snow-linked concentration

The observed concentration is an empirical agreement pattern: in snow-dominated spring high-flow rows, all three evaluated conceptual structures usually had larger MAE than the regional LSTM. Their rainfall-runoff structures differ; GR4J and Xinanjiang share the tested external snow path, whereas HBV-lite uses an intrinsic snow routine. Their shared failure rate exceeds 0.91 in the retained joint context with the highest concentration ratio. This convergence is informative because it is less dependent on the idiosyncrasy of one conceptual formulation, but the analysis does not identify which storage, timing, or event process produced the errors.

At the same time, the analysis cannot determine why the LSTM is better in these rows. Regional learning may exploit cross-basin information, static attributes may condition responses, and the flexible recurrent representation may accommodate temporal dependencies that are constrained in the conceptual models. The present evidence does not separate these explanations. The phrase “snow-linked concentration” therefore denotes an empirical association with basin snow fraction, spring, and high flow; it is not a causal attribution to a particular snow process.

### 4.3 What conceptual references add after predictive dominance

The conceptual models add a coordinate system for error analysis. A single aggregate LSTM score states that the neural model performs better overall, but it does not show whether that margin is spread across ordinary conditions or concentrated in a small set of hydrological contexts. Multiple conceptual structures make it possible to distinguish a structure-specific weakness from a shared pattern. The concentration ratio then compares the frequency of a context with its contribution to the accumulated positive gap.

This diagnostic use does not imply that conceptual models should be attached to the LSTM in deployment. The oracle median gain is zero, and the current analysis contains no validation-selected switching or blending rule. Nor does it imply that the three models span all plausible conceptual structures. The claim is limited to GR4J, Xinanjiang, and HBV-lite under the audited protocol.

### 4.4 Implications for benchmark design

Large-sample model comparisons can separate predictive ranking from diagnostic interpretation. The predictive ranking should be reported plainly and with information differences disclosed. Diagnostic analyses can then ask where errors concentrate, provided that context definitions and post-hoc status are explicit. This separation avoids two common overstatements: treating a lower-performing conceptual model as a competitive predictor, and treating an error association as evidence that a neural network has learned a physically correct process.

The compact concentration table also offers a reusable reporting pattern. A context should not be emphasized only because it has a large average gap; its prevalence and its share of the total positive gap should be shown together. Shared failure adds information about whether the conclusion depends on one conceptual structure. These quantities can be applied to other saved prediction sets, but their scientific interpretation remains specific to the models, data, split, and context definitions used.

### 4.5 Relation to prior work

The result complements, rather than replaces, earlier findings. Kratzert et al. (2019) established strong regional LSTM performance and the value of basin attributes. Lees et al. (2021) documented spatial and seasonal performance patterns in neural-versus-conceptual comparisons. Knoben et al. (2019) emphasized objective comparison across conceptual structures. The present analysis combines these directions in a narrow diagnostic benchmark: three model families are audited under one conceptual protocol, placed below a reproduced LSTM reference, and used to quantify the concentration of the neural advantage. Because related work already covers generic structure comparison and seasonal analysis, the contribution is the integrated, quantitatively traced decomposition rather than the individual ingredients.

## 5. Limitations

The most important limitation is information asymmetry. The LSTM uses regional training and 27 static basin attributes, while the conceptual models are calibrated individually. Sharing basins, forcing, dates, and observed targets does not make the predictive information identical. Accordingly, the paper describes an LSTM reference and conceptual structural probes, not a strict same-information competition.

The decomposition is post-hoc and associational. It uses saved evaluation-period predictions and cannot be interpreted as independent model selection. Contexts are defined by broad regime, season, and flow groups. No event labels identify snowmelt, rainfall-on-snow, frozen-soil effects, or reservoir operations. The snow fraction correlations support population-level alignment but do not establish causal pathways or internal neural representations.

The conceptual sample includes three model families, not the full space of hydrological structures. Shared failure means agreement among GR4J, Xinanjiang, and HBV-lite under this protocol. It is not a theoretical ceiling for conceptual hydrology. Model-specific bounds, numerical implementations, and snow routines remain part of the comparison even though calibration budgets and external conditions were audited.

The daily LSTM residual archive is available for post-hoc analysis, whereas the main headline table remains NSE-based. Selected hydrographs have illustrative value only. The full-population residual analyses reduce but do not remove dependence on the chosen context definitions and error metric. Alternative flow thresholds, seasons, or absolute-error transformations could redistribute the concentration.

Finally, the evidence package is auditable and rebuildable as a registered snapshot. Its 19 external evidence inputs are pinned by byte size and SHA-256 digest and packaged in a single content-pinned local external archive. Extracting that archive into the committed clean checkout reproduces the 14 top-level files. The committed clean checkout has been verified by rebuilding those files twice with zero digest differences. A full conceptual recalibration would be a higher-cost reproduction step, but it is not required for the narrow diagnostic interpretation reported here.

## 6. Conclusions

An aggregate ranking does not reveal how a predictive margin is distributed across hydrological contexts. Across 531 CAMELS-US basins, the reproduced eight-seed LSTM ensemble achieved a median NSE of 0.759225, compared with 0.653287 for the strongest single conceptual model, GR4J. That ranking defines the study boundary rather than its novelty.

The diagnostic decomposition showed that the advantage was disproportionately concentrated in snow-dominated spring and high-flow contexts. Snow-dominated spring rows represented 7.2% of basin-season contexts but 18.6% of the positive gap relative to the lowest-error conceptual model in each row; snow-dominated high-flow rows represented 9.6% of basin-flow contexts but 36.1% of that gap. Population-level analysis supported the same direction: across 531 basins, snow fraction was associated with a wider LSTM margin over the basin-wise conceptual comparator with the highest NSE (rho = 0.429, q = 1.65e-23).

Joint context refinement identified snow-dominated spring high flow as the retained joint context with the highest concentration ratio. It represented 2.8% of joint rows and accounted for 13.6% of the positive gap; all three conceptual models had higher mean absolute error than the LSTM in 91.4% of those rows. These results support a diagnostic role for three conceptual structures after predictive dominance has been established. They do not establish a validation-selected, deployable predictive complement, causal event attribution, or LSTM process realism.

## Data and Code Availability

The manuscript evidence package is stored under `draft/papers/10_18_conceptual_lstm_package`. Nineteen external evidence inputs are registered by relative path, role, byte size, and SHA-256 digest and packaged in a single content-pinned local external archive. Core numbers are mapped to structured output cells in `reproducibility/core_evidence_map.csv`. The package build command is `python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package --verify-snapshot`. The committed clean checkout plus the extracted archive reproduces the registered snapshot; no working-tree overlay is required.

## Reference Sources Used in This Draft

- Addor et al. (2017), source for the CAMELS attribute and large-sample comparative hydrology context: https://hess.copernicus.org/articles/21/5293/2017/
- Kratzert et al. (2019), source for regional LSTM performance across 531 CAMELS-US basins: https://hess.copernicus.org/articles/23/5089/2019/
- Knoben et al. (2019), source for objective modular conceptual-model structure comparison: https://gmd.copernicus.org/articles/12/2463/2019/
- Lees et al. (2021), source for spatial and seasonal LSTM-versus-conceptual performance patterns: https://hess.copernicus.org/articles/25/5517/2021/
- Wang et al. (2026), source for recent event-type and multidimensional hydrological model diagnostics: https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2025WR040264
- CAMELS benchmark model outputs, source for the common Maurer forcing and reverse split: https://www.hydroshare.org/resource/474ecc37e7db45baa425cdb4fc1b61e1/
