#!/usr/bin/env bash
# ID33 : full state snapshot before the clean rerun. Read-only.
set -o pipefail
echo "=== STAMP ==="; date -Is
R=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo/results/33_transformer_recipe_repair

echo "=== A. ALL EIGHT JOBS, FINAL STATE ==="
sacct -j 220490,220491,220492,220493,220494,220495,220658,220659 -X \
  --format=JobID%9,JobName%9,State%11,ExitCode%7,Elapsed%10,End%17,NodeList%8 2>&1 || true

echo "=== B. ANYTHING OF MINE STILL RUNNING ==="
squeue -u "$USER" -o "%.9i %.14j %.9P %.2t %.11M %.14R" 2>&1 | head -14 || true

echo "=== C. MANIFEST STATUS PER ARM ==="
python - "$R" <<'PY' 2>&1 || true
import json, sys
from pathlib import Path
inv = Path(sys.argv[1]) / "_invocations"
for d in sorted(inv.iterdir()) if inv.is_dir() else []:
    p = d / "run_manifest.json"
    if not p.is_file(): continue
    m = json.loads(p.read_text(encoding="utf-8"))
    print("  %-34s status=%-9s rc=%-5s med=%s" % (
        d.name, m.get("status"), m.get("training_return_code"),
        m.get("median_nse_epoch030", "-")))
PY

echo "=== D. EPOCH-30 METRICS PRESENT AND MEDIAN (data validity, independent of manifest) ==="
python - "$R" <<'PY' 2>&1 || true
import csv, math, statistics, sys
from pathlib import Path
root = Path(sys.argv[1])
for arm in ("T1","T2","T3","T4","T5","L33","C1","C2"):
    hits = sorted((root/arm).glob("*/validation/model_epoch030/validation_metrics.csv")) if (root/arm).is_dir() else []
    if not hits: print(f"  {arm}: no epoch-30 file"); continue
    rows = list(csv.DictReader(hits[0].open(encoding="utf-8")))
    col = "NSE" if rows and "NSE" in rows[0] else list(rows[0].keys())[-1]
    v = [float(r[col]) for r in rows if r.get(col) and math.isfinite(float(r[col]))]
    print(f"  {arm}: basins={len(rows)} finite={len(v)} median={statistics.median(v):.6f}")
PY

echo "=== E. BEST EPOCH PER ARM (protocol scores ep30, but report the peak too) ==="
for a in T1 T2 T3 T4 T5 L33 C1 C2; do
  f=$(find "$R/$a" -name output.log -type f 2>/dev/null | head -1)
  test -n "$f" && echo "  $a best: $(grep -o 'NSE: [0-9.]*' "$f" 2>/dev/null | sed 's/NSE: //' | sort -g | tail -1)  ep30: $(grep 'Median validation metrics' "$f" 2>/dev/null | tail -1 | sed 's/.*NSE: //')" || echo "  $a: no log"
done

echo "=== F. GPU AVAILABILITY FOR THE RERUN ==="
sinfo -o "%.9P %.6D %.8t %.30N" 2>&1 | grep -E 'PARTITION|hgpu2' || true
echo ID33_SNAPSHOT_COMPLETE
