#!/bin/bash
set -o pipefail
R=/data1/home/sunyiq/zhenjiang_oyv_v1
python - <<'PYEOF' 2>&1 | sed 's/^/  /'
import csv, statistics as st
rows=list(csv.DictReader(open("/data1/home/sunyiq/zhenjiang_oyv_v1/n4_impact/n4_task_errors.csv",encoding="utf-8-sig")))
print("=== absolute forecast error, full six stations available ===")
for tgt in ("nanjing","xuliujing"):
    for h in (1,3,6,12,24):
        v=[float(r["mean_absolute_error_m"]) for r in rows
           if r["target"]==tgt and r["condition"]=="complete_observation"
           and int(r["horizon_hours"])==h]
        if v: print("  %-10s H=%-2d  MAE = %.4f m   (n=%d runs, spread %.4f-%.4f)"%(
            tgt,h,st.median(v),len(v),min(v),max(v)))
print()
print("=== same but target station itself already failed (hidden_target) ===")
for tgt in ("nanjing","xuliujing"):
    for h in (1,6):
        v=[float(r["mean_absolute_error_m"]) for r in rows
           if r["target"]==tgt and r["condition"]=="hidden_target"
           and int(r["horizon_hours"])==h]
        if v: print("  %-10s H=%-2d  MAE = %.4f m"%(tgt,h,st.median(v)))
PYEOF
echo "=== DONE ==="
