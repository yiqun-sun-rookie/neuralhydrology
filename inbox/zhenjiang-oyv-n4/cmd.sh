#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
echo "=== WAIT (max 20 min) ==="
for i in $(seq 1 120); do
  LEFT=0
  for j in 212950 212951; do
    st=$(sacct -j "$j" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
    case "$st" in RUNNING|PENDING|"") LEFT=$((LEFT+1));; esac
  done
  [ "$LEFT" -eq 0 ] && { echo "  settled t=$((i*10))s"; break; }
  sleep 10
done
for j in 212950 212951; do sacct -j "$j" -X --format=JobID%9,JobName%8,NodeList%8,State%11,ExitCode%7,Elapsed%9 2>&1 | tail -1; done
echo "=== SUMMARY LINES ONLY ==="
for j in 212950 212951; do
  echo "  ==== $j ===="
  f="$ROOT/probe/platform_${j}.out"
  if [ -f "$f" ]; then
    grep -E '"(node_name|graphics_processor_name|tasks_compared|failures|largest_absolute_mae_difference_m|effect_floor_m|ratio_of_worst_difference_to_floor)"' "$f" | tail -8 | sed 's/^/    /'
    echo "    -- per-task worst differences --"
    python - "$f" <<'PYEOF' 2>&1 | sed 's/^/    /'
import json, sys, re
txt = open(sys.argv[1], encoding="utf-8").read()
start = txt.rfind('{\n  "effect_floor_m"')
if start < 0:
    start = txt.rfind('{\n  "failures"')
if start < 0:
    print("no final report object found"); raise SystemExit
try:
    rep = json.loads(txt[start:])
except Exception as e:
    print("parse failed:", e); raise SystemExit
for r in rep.get("rows", []):
    if r.get("status") != "COMPARED":
        print(r.get("task_id"), r.get("status")); continue
    ph = r["per_horizon"]
    worst = max(abs(v["difference_m"]) for v in ph.values())
    h1 = ph.get("1") or ph.get(1)
    print("%-70s worst|d|=%.6f  h1 stored=%.5f rerun=%.5f" % (
        r["task_id"][:70], worst, h1["stored_mae_m"], h1["rerun_mae_m"]))
print("OVERALL worst |dMAE| = %.6f m   floor = %.3f m   ratio = %.4f" % (
    rep["largest_absolute_mae_difference_m"], rep["effect_floor_m"],
    rep["ratio_of_worst_difference_to_floor"]))
PYEOF
  else echo "    no log"; fi
done
echo "  n4_tasks: $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
echo "=== DONE ==="
