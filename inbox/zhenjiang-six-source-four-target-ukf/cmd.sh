#!/bin/bash
set -o pipefail
EV="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260902_recovery_attempt_002/evidence/development_2023/evaluation/attempt_002"
printf '=== SNAPSHOT_TIME ===\n'; date -Is
printf '=== PER_STATION_GAIN_AND_CONTRACTION_POOLED ===\n'
python - "${EV}" <<'PY' 2>&1 || true
import csv, sys, collections, json
p = sys.argv[1] + "/analysis_observation_sufficient_statistics.csv"
agg = collections.defaultdict(lambda: collections.defaultdict(float))
seeds = set()
with open(p, newline="") as h:
    for r in csv.DictReader(h):
        s = r["source_station"]; seeds.add(r["seed"])
        a = agg[s]
        a["cells"] += float(r["cell_count"])
        a["prior_abs"] += float(r["prior_absolute_residual_sum_m"])
        a["post_abs"] += float(r["posterior_absolute_residual_sum_m"])
        a["innov_abs"] += float(r["innovation_absolute_sum_m"])
        a["k_norm"] += float(r["kalman_gain_norm_sum"])
        a["post_var"] += float(r["posterior_observation_variance_sum_normalized"])
        a["near_zero"] += float(r["near_zero_prior_count"])
print("seeds=" + ",".join(sorted(seeds)))
order = ["datong","nanjing","zhenjiang","jiangyin","xuliujing","wusongkou"]
print("station|cells|prior_mae_m|post_mae_m|contraction|mean_K_norm|mean_post_obs_var_norm|near_zero_prior")
for s in order:
    a = agg[s]; n = a["cells"] or 1.0
    print("%s|%d|%.5f|%.5f|%.4f|%.4f|%.5f|%d" % (s, n, a["prior_abs"]/n, a["post_abs"]/n, (a["post_abs"]/n)/(a["prior_abs"]/n), a["k_norm"]/n, a["post_var"]/n, a["near_zero"]))
PY
printf '=== EVALUATION_FILE_LIST (confirm no cross-station response product) ===\n'
python - "${EV}" <<'PY' 2>&1 || true
import json, sys
m = json.load(open(sys.argv[1] + "/completion_manifest.json"))
for f in m.get("files", []):
    print("FILE|%s|%d" % (f["name"], f["byte_count"]))
PY
printf '=== GAIN_MATRIX_COLUMNS_WITH_CROSS ===\n'
head -n 1 "${EV}/six_source_four_target_gain_matrix.csv" 2>/dev/null | tr ',' '\n' | grep -niE "cross|response|posterior_obs|analysis" || echo "no cross-response columns"
printf '=== SNAPSHOT_END ===\n'; date -Is
exit 0
