#!/bin/bash
# precip-selfrule-v05 seq=16: summarize the eight-basin technical run if all records are complete.
set -eo pipefail
ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929_r03
CODE="$ROOT/code"
ASSET="$ROOT/assets/c4_s100"
DATA="$HOME/neuralhydrology/data/camels_us"
OUT="$ROOT/technical_8/run01"
BASINS="$CODE/src/precip_input_assimilation/configs/basins_8_selfrule_v05.txt"

date "+wallclock %F %T %z"
echo "=== FINAL ARRAY STATUS ==="
squeue -j 231259,231273 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
sacct -j 231259,231273 --format=JobID,JobName%24,State,ExitCode,Elapsed,AllocTRES%40,MaxRSS,NodeList%14 -P || true

complete=$(python - "$OUT" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])/'fit'
count=0
for path in root.glob('*.json') if root.exists() else []:
    try: data=json.loads(path.read_text())
    except Exception: continue
    count += data.get('technical_complete') is True
print(count)
PY
)
echo "COMPLETE_RECORDS=$complete"
if test "$complete" -ne 8; then
  echo "TECHNICAL_RECORDS_PENDING"
  exit 0
fi

test ! -e "$OUT/technical_summary.json" || { echo "TECHNICAL_SUMMARY_ALREADY_EXISTS"; cat "$OUT/technical_summary.json"; exit 0; }
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export PYTHONPATH="$CODE/src:$HOME/neuralhydrology:${PYTHONPATH:-}"
python -u "$CODE/src/precip_input_assimilation/scripts/summarize_selfrule_technical_v05.py" \
  --output-dir "$OUT" \
  --basin-file "$BASINS" \
  --data-dir "$DATA" \
  --run-dir "$ASSET" \
  --device cuda:0
cat "$OUT/technical_summary.json"
