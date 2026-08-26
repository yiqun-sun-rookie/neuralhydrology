#!/bin/bash
# Finish: wait out the last tasks, verify every artefact, run the impact stage
# with its mechanical prediction verdicts, then the independent audit.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. WAIT FOR THE LAST TASKS (max 25 min) ==="
for i in $(seq 1 150); do
  N=$(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l)
  [ "$N" -ge 1440 ] && { echo "  all 1440 present at t=$((i*10))s"; break; }
  [ $((i % 12)) -eq 0 ] && echo "  t=$((i*10))s n4=$N/1440"
  sleep 10
done
echo "  final count: $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
for j in 213598 213599; do
  echo -n "  ARRAY $j "
  sacct -j "$j" -X -n -P -o State 2>/dev/null | sort | uniq -c | tr '\n' ' '
  echo
done

echo "=== B. ENVIRONMENT ==="
cd "$ROOT/repo" || exit 1
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || echo "  fetch failed, using current"
git reset -q --hard refs/remotes/origin/main
echo "  head: $(git log --oneline -1)"
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"

echo "=== C. ARTEFACT COMPLETENESS ==="
python - <<'PYEOF'
import os, sys
sys.path.insert(0, "scripts/analysis"); sys.path.insert(0, "scripts/modeling")
import zhenjiang_oyv_n4_contract as c
root = "/data1/home/sunyiq/zhenjiang_oyv_v1/n4_tasks"
need = {"best_state.pt","training_history.csv","test_predictions.npz","run_identity.json","completion_manifest.json"}
bad = [t["task_id"] for t in c.enumerate_tasks()
       if not (os.path.isdir(os.path.join(root, str(t["task_id"])))
               and need <= set(os.listdir(os.path.join(root, str(t["task_id"])))))]
print("  incomplete tasks:", len(bad))
for b in bad[:5]: print("   ", b)
PYEOF

echo "=== D. IMPACT AND PREDICTION VERDICTS ==="
rm -rf "$ROOT/n4_impact"
python -u scripts/analysis/zhenjiang_oyv_n4_impact.py \
  --task-root "$ROOT/n4_tasks" \
  --output-root "$ROOT/n4_impact" \
  --information-root "$ROOT/repo/results/analysis/gauge_network_mutual_information_v4_tide_conditioned" 2>&1 | tail -30

echo "=== E. VERDICT TABLE ==="
python - <<'PYEOF' 2>&1 | sed 's/^/  /'
import csv, json
p = "/data1/home/sunyiq/zhenjiang_oyv_v1/n4_impact/n4_prediction_verdicts.csv"
try:
    rows = list(csv.DictReader(open(p, encoding="utf-8-sig")))
except Exception as e:
    print("could not read verdicts:", e); raise SystemExit
for r in rows:
    print("%-6s %-10s %-9s passed=%-5s %s" % (
        r["prediction"], r["target"], r["tier"], r["passed"], r["detail"][:150]))
PYEOF

echo "=== F. STATION RANKING ==="
head -25 "$ROOT/n4_impact/n4_station_ranking.csv" 2>/dev/null | sed 's/^/  /'

echo "=== G. DONE ==="
