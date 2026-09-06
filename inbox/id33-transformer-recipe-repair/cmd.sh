#!/usr/bin/env bash
set -o pipefail
echo "=== STAMP ==="; date -Is
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
ID30=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
cd "$ID33"
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null && conda activate nh_final 2>/dev/null
python -c "import sys;print(sys.version)" || true

echo "=== A. ID30 BASELINE PATHS (read-only) ==="
find "$ID30" -maxdepth 6 -type d -name "model_epoch030" 2>/dev/null | grep -E "/(B01|D01)/" | head -10 || true

echo "=== B. WIDE PER-BASIN TABLE ==="
python - <<'PY'
import glob, os, csv
id33="/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo/results/33_transformer_recipe_repair"
id30="/data1/home/sunyiq/id30_modern_transformer_moe_20260827"
cols={}
def load(p):
    d={}
    with open(p) as f:
        for row in csv.DictReader(f):
            b=row.get('basin') or row.get('gauge_id')
            v=row.get('NSE')
            if b is None or v is None: continue
            d[str(b).zfill(8)]=v
    return d
for a in ["T1","T2","T3","T4","T5","L33"]:
    g=sorted(glob.glob(os.path.join(id33,a,"*","validation","model_epoch030","validation_metrics.csv")))
    if g: cols[a]=load(g[-1]); print("#",a,g[-1],len(cols[a]))
    else: print("#",a,"MISSING")
for a in ["D01","B01"]:
    g=sorted(glob.glob(os.path.join(id30,"**",a,"*","validation","model_epoch030","validation_metrics.csv"),recursive=True))
    if g: cols[a]=load(g[-1]); print("#",a,g[-1],len(cols[a]))
    else: print("#",a,"MISSING")
keys=[k for k in ["T1","T2","T3","T4","T5","L33","D01","B01"] if k in cols]
basins=sorted(set().union(*[set(cols[k]) for k in keys])) if keys else []
print("basin,"+",".join(keys))
for b in basins:
    print(b+","+",".join(cols[k].get(b,"") for k in keys))
PY

echo "=== C. GPU UTIL DETAIL ==="
for f in logs/33_transformer_recipe_repair/utilisation-*.csv; do
  test -f "$f" || continue
  echo "-- $f"; head -3 "$f"; tail -2 "$f"
  awk -F, 'NR>1{u+=$2;m+=$3;c++; if($2>mx)mx=$2} END{if(c)printf("   n=%d gpu_util mean=%.1f%% max=%s mem mean=%.0f MiB\n",c,u/c,mx,m/c)}' "$f" || true
done
echo DONE
