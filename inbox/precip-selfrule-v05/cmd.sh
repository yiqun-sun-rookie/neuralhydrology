#!/bin/bash
# precip-selfrule-v05 seq=33: read-only closure evidence for failed concurrency probe 231412.
set -eo pipefail

ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_concurrency4_probe_20260929
OUT="$ROOT/candidate_concurrency4/run01"
JOB=231412
MEM="$ROOT/logs/gpu-memory-$JOB.txt"

date "+wallclock %F %T %z"
sacct -j "$JOB" --format=JobIDRaw,JobName%24,State,ExitCode,Elapsed,ElapsedRaw,AllocTRES%40,MaxRSS,NodeList%14 -P
if [ -f "$MEM" ]; then
  echo "GPU_MEMORY_SAMPLES=$(wc -l < "$MEM")"
  awk 'BEGIN {max=0; ts=0} {if ($2+0>max) {max=$2+0; ts=$1}} END {print "GPU_PEAK_USED_MIB=" max; print "GPU_PEAK_EPOCH=" ts}' "$MEM"
  echo "GPU_LAST_SAMPLE=$(tail -1 "$MEM")"
fi
python - "$OUT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for basin in ("02137727", "02245500", "09404450", "09512280"):
    fit = root / "fit" / f"{basin}.json"
    pred = root / "predictions" / f"{basin}.npz"
    if fit.is_file():
        payload = json.loads(fit.read_text(encoding="utf-8"))
        print("BASIN", basin, "FIT_EXISTS", True, "COMPLETE", payload.get("technical_complete"),
              "REASON", payload.get("reason"), "PREDICTION_EXISTS", pred.is_file())
    else:
        print("BASIN", basin, "FIT_EXISTS", False, "PREDICTION_EXISTS", pred.is_file())
print("TIMING_EXISTS", (root / "concurrency_timing.json").is_file())
print("COMPARISON_EXISTS", (root / "concurrency_probe_comparison.json").is_file())
PY
