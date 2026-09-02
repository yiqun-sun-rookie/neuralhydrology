#!/usr/bin/env bash
# seq=70 : verify the ID30 D01 / B01 targets and inspect their training curves. Read-only.
set -o pipefail
ID30=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo
RES="$ID30/results/30_modern_transformer_moe"

echo "=== A. ID30 ARM INVENTORY ==="
for arm in B01 D01 D02 D03 M01; do
  if test -d "$RES/$arm"; then
    echo "$arm : dir_exists"
    find "$RES/$arm" -maxdepth 1 -mindepth 1 -type d -printf '    %f\n' 2>/dev/null | head -4 || true
  else echo "$arm : NO_DIR"; fi
done
echo "-- invocation records --"
find "$RES/_invocations" -maxdepth 1 -mindepth 1 -type d -printf '  %f\n' 2>/dev/null | sort || true

echo "=== B. EPOCH-30 MEDIAN NSE PER ARM (with hashes) ==="
python - "$RES" <<'PY' 2>&1 || true
import csv, math, hashlib
from pathlib import Path
import sys
res = Path(sys.argv[1])
for arm in ("B01","D01","D02","D03","M01"):
    d = res/arm
    if not d.is_dir(): print(arm, "NO_DIR"); continue
    for run in sorted(d.iterdir()):
        if not run.is_dir(): continue
        f = run/"validation"/"model_epoch030"/"validation_metrics.csv"
        if not f.is_file():
            eps = sorted((run/"validation").glob("model_epoch*")) if (run/"validation").is_dir() else []
            print(arm, run.name, "NO_EPOCH030 last_epoch_dirs=", [e.name for e in eps[-2:]]); continue
        rows = list(csv.DictReader(f.open(encoding="utf-8")))
        col = "NSE" if rows and "NSE" in rows[0] else list(rows[0].keys())[-1]
        v = sorted(float(r[col]) for r in rows
                   if r.get(col) and math.isfinite(float(r[col])))
        n=len(v); med = v[n//2] if n%2 else 0.5*(v[n//2-1]+v[n//2])
        h = hashlib.sha256(f.read_bytes()).hexdigest()
        print("%-4s rows=%d finite=%d median=%.6f  %s  %s" % (arm,len(rows),n,med,h,run.name))
PY

echo "=== C. D01 TRAINING CURVE (all epochs) ==="
D01LOG=$(find "$RES/D01" -name output.log -type f 2>/dev/null | head -1)
if test -n "$D01LOG"; then
  echo "LOG $D01LOG"
  grep -E 'Epoch [0-9]+ average loss|Epoch [0-9]+ average validation' "$D01LOG" 2>&1 || true
else echo "D01_LOG_NOT_FOUND"; fi

echo "=== D. B01 TRAINING CURVE (all epochs) ==="
B01LOG=$(find "$RES/B01" -name output.log -type f 2>/dev/null | head -1)
if test -n "$B01LOG"; then
  echo "LOG $B01LOG"
  grep -E 'Epoch [0-9]+ average loss|Epoch [0-9]+ average validation' "$B01LOG" 2>&1 || true
else echo "B01_LOG_NOT_FOUND"; fi

echo "=== E. B01 CONFIG (protocol match check) ==="
cat "$ID30/src/modern_transformer_moe/configs/baseline_lstm_s100.yml" 2>&1 || true

echo "=== F. DATA BUNDLE (shared, read-only) ==="
ls -la "$ID30/data/camels_us_track0_development_forcing_v01/" 2>&1 | head -8 || true
du -sh "$ID30/data/camels_us_track0_development_forcing_v01" "$ID30/data/camels_us_track0_supervision_v01" 2>&1 || true

echo "ID32_TARGET_VERIFY_COMPLETE"
