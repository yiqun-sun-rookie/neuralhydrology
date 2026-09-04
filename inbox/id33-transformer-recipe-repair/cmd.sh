#!/usr/bin/env bash
# ID33 seq=10 : scope the integrity break I caused by deploying mid-flight, and answer
# "is anything held but idle". Read-only.
set -o pipefail
echo "=== STAMP ==="; date -Is; NOW=$(date +%s)
INV=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo/results/33_transformer_recipe_repair/_invocations

echo "=== A. EXACTLY WHICH FILES DIFFER FOR L33 (before vs after) ==="
python - "$INV/id33_L33_s100_slurm220495/run_manifest.json" <<'PY' 2>&1 || true
import json, sys
from pathlib import Path
m = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
b = m.get("source_integrity_before", {}); a = m.get("source_integrity_after", {})
if not a:
    print("  no source_integrity_after recorded (the run raised before writing it)")
bi = b.get("implementation_files", {}); ai = a.get("implementation_files", {})
if ai:
    for k in sorted(set(bi) | set(ai)):
        if bi.get(k) != ai.get(k):
            print(f"  DIFFERS {k}\n    before={bi.get(k)}\n    after ={ai.get(k)}")
print("  own config before:", b.get("config_file"))
print("  own config after :", a.get("config_file", "not recorded"))
PY

echo "=== B. IS EACH ARM'S OWN CONFIG STILL AT ITS REGISTERED HASH ==="
cd /data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
for f in l33 t1 t2 t3 t4 t5; do sha256sum "src/transformer_recipe_repair/configs/$f.yml" 2>&1; done

echo "=== C. WILL T1..T5 HIT THE SAME THING? (start time vs my 16:08 deploy) ==="
sacct -j 220490,220491,220492,220493,220494,220495 -X --format=JobID%9,JobName%9,State%10,Start%20,Elapsed%10 -n -P 2>&1 || true

echo "=== D. HELD BUT IDLE? log staleness for every running job ==="
R=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo/results/33_transformer_recipe_repair
for a in T1 T2 T3 T4 T5 C1 C2; do
  f=$(find "$R/$a" -name output.log -type f 2>/dev/null | head -1)
  if test -n "$f"; then
    AGE=$(( NOW - $(stat -c %Y "$f") ))
    n=$(grep -c 'average validation loss' "$f" 2>/dev/null || true)
    FLAG=OK; [ "$AGE" -gt 3600 ] && FLAG=SUSPECT_STALL
    echo "  $a epochs=${n:-0} log_idle=${AGE}s $FLAG"
  else echo "  $a no log"; fi
done

echo "=== E. THROUGHPUT: minutes per epoch, 3090 arms vs A800 calibration ==="
for a in T1 T4 C1; do
  f=$(find "$R/$a" -name output.log -type f 2>/dev/null | head -1)
  test -n "$f" && { echo "  -- $a --"; grep -E 'Epoch [0-9]+ average loss' "$f" 2>/dev/null | awk '{print $1, $2, $4}' | tail -3 || true; }
done
echo "  (ID30 D01 on a 3090 at batch 64 was 12.8 min/epoch)"

echo "=== F. C1 AND C2 SHARE ngu201 - are they contending? ==="
scontrol show node ngu201 2>/dev/null | tr ' ' '\n' | grep -E '^(NodeName|CPUAlloc|CPUTot|AllocTRES|State)=' | tr '\n' ' '; echo
echo ID33_SCOPE_SEQ10_COMPLETE
