#!/bin/bash
set -o pipefail
R=/data1/home/sunyiq/zhenjiang_oyv_v1/n4_impact
echo "=== XULIUJING RANKING ==="
grep '^xuliujing' "$R/n4_station_ranking.csv" 2>/dev/null | sed 's/^/  /'
echo "=== NANJING PAIR AND FAILURE COST (against complete_observation) ==="
python - <<'PYEOF' 2>&1 | sed 's/^/  /'
import csv
p="/data1/home/sunyiq/zhenjiang_oyv_v1/n4_impact/n4_cost_summary.csv"
rows=list(csv.DictReader(open(p,encoding="utf-8-sig")))
for tgt in ("nanjing","xuliujing"):
    for h in (1,6):
        r=[x for x in rows if x["measured_against"]=="complete_observation"
           and x["target"]==tgt and x["condition"]=="hidden_target"
           and int(x["horizon_hours"])==h]
        if r: print("%s H=%d  failure cost vs full six = %.5f m (folds +%s/%s)"%(
            tgt,h,float(r[0]["median_cost_m"]),r[0]["positive_fold_years"],r[0]["fold_count"]))
    for cond in ("hidden_target_both_nearest","endpoints_only"):
        r=[x for x in rows if x["measured_against"]=="hidden_target"
           and x["target"]==tgt and x["condition"]==cond and int(x["horizon_hours"])==1]
        if r: print("  %s %s H=1 = %.5f m"%(tgt,cond,float(r[0]["median_cost_m"])))
PYEOF
echo "=== ABLATION vs INFORMATION ORDERING ==="
head -12 "$R/n4_information_comparison.csv" 2>/dev/null | sed 's/^/  /'
echo "=== DONE ==="
