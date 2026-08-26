#!/bin/bash
# Inventory: what actually completed before the cancel, and what is missing.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. ARRAY OUTCOMES ==="
for j in 212898 212901 212902; do
  echo "  ---- $j ----"
  sacct -j "$j" -X -n -P -o JobID,State,ExitCode,Elapsed,NodeList 2>/dev/null | head -3
  sacct -j "$j" -X -n -P -o State 2>/dev/null | sort | uniq -c | sort -rn | sed 's/^/    /'
done

echo "=== B. TASK DIRECTORY INVENTORY ==="
echo "  n4_tasks dirs   : $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l)"
echo "  n4_smoke dirs   : $(ls -1 "$ROOT/n4_smoke" 2>/dev/null | wc -l)"
echo "  complete (5 artefacts):"
python - <<'PYEOF'
import os, json
root = "/data1/home/sunyiq/zhenjiang_oyv_v1/n4_tasks"
need = {"best_state.pt","training_history.csv","test_predictions.npz","run_identity.json","completion_manifest.json"}
if not os.path.isdir(root):
    print("    (n4_tasks absent)"); raise SystemExit
names = sorted(os.listdir(root))
full, partial = [], []
nodes = {}
for n in names:
    have = set(os.listdir(os.path.join(root, n)))
    (full if need <= have else partial).append(n)
    try:
        d = json.load(open(os.path.join(root, n, "run_identity.json"), encoding="utf-8"))
        nd = d.get("runtime_environment", {}).get("node_name", "?")
        nodes[nd] = nodes.get(nd, 0) + 1
    except Exception:
        pass
print("    complete =", len(full), " partial =", len(partial))
if partial: print("    partial examples:", partial[:5])
print("    by node:", nodes)
import re
def parse(n):
    m = re.match(r"zhenjiang_oyv_n4__fold_(\d+)__(\w+?)__(.+)__seed_(\d+)$", n)
    return m.groups() if m else None
tg = {}
for n in full:
    p = parse(n)
    if p: tg[p[1]] = tg.get(p[1], 0) + 1
print("    complete by target:", tg)
PYEOF

echo "=== C. WHICH GLOBAL INDICES ARE MISSING ==="
cd "$ROOT/repo" || exit 1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"
python - <<'PYEOF'
import os, sys
sys.path.insert(0, "scripts/analysis"); sys.path.insert(0, "scripts/modeling")
import zhenjiang_oyv_n4_contract as c
root = "/data1/home/sunyiq/zhenjiang_oyv_v1/n4_tasks"
need = {"best_state.pt","training_history.csv","test_predictions.npz","run_identity.json","completion_manifest.json"}
tasks = c.enumerate_tasks()
missing = []
for i, t in enumerate(tasks):
    d = os.path.join(root, str(t["task_id"]))
    if not os.path.isdir(d) or not need <= set(os.listdir(d)):
        missing.append(i)
print("  total", len(tasks), "missing", len(missing))
if missing:
    print("  first 10 missing:", missing[:10])
    print("  last 10 missing:", missing[-10:])
    lo = [m for m in missing if m < 720]; hi = [m for m in missing if m >= 720]
    print("  missing in half one (0-719):", len(lo))
    print("  missing in half two (720-1439):", len(hi))
open("/data1/home/sunyiq/zhenjiang_oyv_v1/missing_indices.txt","w").write(",".join(str(m) for m in missing))
print("  written missing_indices.txt")
PYEOF

echo "=== D. SAMPLE RUN IDENTITY ==="
S=$(ls -d "$ROOT/n4_tasks"/*/ 2>/dev/null | head -1)
[ -n "$S" ] && python - "$S/run_identity.json" <<'PYEOF' 2>&1 | sed 's/^/    /'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
for k in ("task_id","target","condition","test_year","seed","test_sample_count"): print(k,"=",d.get(k))
rt=d.get("runtime_environment",{})
for k in ("node_name","graphics_processor_name","graphics_processor_driver_version","operating_system"): print(k,"=",rt.get(k))
print("fold_isolation_findings =", d.get("fold_isolation",{}).get("finding_count"))
PYEOF

echo "=== E. QUEUE NOW ==="
squeue -u "$USER" -h -o "%.20i %.12j %.12P %.9T" 2>/dev/null | head -12 || true
sinfo -p hgpu2p,hgpu2 -o "%.10P %.6D %.6t %.30N" 2>&1 | head -8 || true
echo "=== DONE ==="
