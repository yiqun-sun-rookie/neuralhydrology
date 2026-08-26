#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
N4=$(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l)
echo "PROGRESS n4=${N4}/1440"
for j in 213598 213599; do
  echo -n "ARRAY $j "
  sacct -j "$j" -X -n -P -o State 2>/dev/null | sort | uniq -c | tr '\n' ' '
  echo
done
FAILS=$(sacct -X -n -P -S 2026-08-26 -o JobID,JobName,State 2>/dev/null | grep -E '\|(FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY)' | grep zj_oyv_n4 | head -5)
[ -n "$FAILS" ] && { echo "TROUBLE:"; echo "$FAILS"; } || echo "TROUBLE none"
if [ "$N4" -ge 1440 ]; then
  echo "N4_COMPLETE verifying artefacts"
  cd "$ROOT/repo" || exit 1
  source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
  conda activate nh_final 2>/dev/null
  export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"
  python - <<'PYEOF'
import os, sys
sys.path.insert(0, "scripts/analysis"); sys.path.insert(0, "scripts/modeling")
import zhenjiang_oyv_n4_contract as c
root = "/data1/home/sunyiq/zhenjiang_oyv_v1/n4_tasks"
need = {"best_state.pt","training_history.csv","test_predictions.npz","run_identity.json","completion_manifest.json"}
bad = [t["task_id"] for t in c.enumerate_tasks()
       if not (os.path.isdir(os.path.join(root, str(t["task_id"])))
               and need <= set(os.listdir(os.path.join(root, str(t["task_id"])))))]
print("INCOMPLETE_TASKS", len(bad))
PYEOF
fi
echo "=== DONE ==="
