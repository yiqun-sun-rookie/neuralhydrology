#!/bin/bash
set -o pipefail
EV="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260902_recovery_attempt_002/evidence/development_2023/evaluation/attempt_002"
printf '=== SNAPSHOT_TIME ===\n'; date -Is
printf '=== STATE_DIFFERENCE_DIAGNOSTICS_CSV ===\n'
cat "${EV}/state_difference_diagnostics.csv" 2>&1 || true
printf '=== OBS_SUFFICIENT_STATS_HEADER ===\n'
head -n 2 "${EV}/analysis_observation_sufficient_statistics.csv" 2>&1 || true
printf 'rows=%s\n' "$(wc -l < "${EV}/analysis_observation_sufficient_statistics.csv" 2>/dev/null)"
printf '=== CROSS_RESPONSE_6x6 (posterior_obs_j - prior_obs_j, mean over origins, per assimilated source i) ===\n'
python - "${EV}" <<'PY' 2>&1 || true
import csv, sys, collections
path = sys.argv[1] + "/analysis_observation_sufficient_statistics.csv"
with open(path, newline="") as h:
    r = csv.DictReader(h)
    cols = r.fieldnames
    print("columns=" + "|".join(cols))
    acc = collections.defaultdict(lambda: collections.defaultdict(float))
    cnt = collections.defaultdict(lambda: collections.defaultdict(float))
    keys = [c for c in cols if "sum" in c or "count" in c]
    print("sum_like_columns=" + "|".join(keys))
    n = 0
    for row in r:
        n += 1
        if n > 5:
            break
        print("sample_row=" + str({k: row[k] for k in cols[:12]}))
PY
printf '=== SNAPSHOT_END ===\n'; date -Is
exit 0
