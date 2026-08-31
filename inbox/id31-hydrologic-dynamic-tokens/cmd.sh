#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
test -d "$ROOT/.git"
cd "$ROOT"

echo "=== ID31 PROGRESS SNAPSHOT ==="
date -Is
hostname

for SPEC in DT08:215879 DL01:215880; do
  EXPERIMENT_ID="${SPEC%%:*}"
  JOB_ID="${SPEC##*:}"
  RUN_ID="id31_${EXPERIMENT_ID}_s100_slurm${JOB_ID}"
  RUN_ROOT="results/31_hydrologic_dynamic_tokens/${EXPERIMENT_ID}"
  MANIFEST="results/31_hydrologic_dynamic_tokens/_invocations/${RUN_ID}/run_manifest.json"
  STDOUT="logs/31_hydrologic_dynamic_tokens/development-${JOB_ID}.out"
  STDERR="logs/31_hydrologic_dynamic_tokens/development-${JOB_ID}.err"

  echo "=== ${EXPERIMENT_ID} JOB ${JOB_ID}: SCHEDULER ==="
  squeue -j "$JOB_ID" -o '%.18i %.12P %.30j %.2t %.10M %.20R' || true
  sacct -j "$JOB_ID" --format=JobID,JobName%30,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P || true

  echo "=== ${EXPERIMENT_ID}: RUN MANIFEST ==="
  if [ -f "$MANIFEST" ]; then
    sha256sum "$MANIFEST"
    cat "$MANIFEST"
  else
    echo "RUN_MANIFEST_MISSING $MANIFEST"
  fi

  echo "=== ${EXPERIMENT_ID}: KEY ARTIFACTS ==="
  if [ -d "$RUN_ROOT" ]; then
    find "$RUN_ROOT" -maxdepth 5 -type f \
      \( -name 'epoch030_metrics.json' -o -name 'model_epoch030.pt' -o -name 'validation_metrics.csv' \
         -o -name 'validation_results.p' -o -name 'config.yml' -o -name 'output.log' \) \
      -printf '%TY-%Tm-%TdT%TH:%TM:%TS%Tz %s %p\n' | sort
    while IFS= read -r METRICS; do
      echo "METRICS_FILE $METRICS"
      sha256sum "$METRICS"
      cat "$METRICS"
    done < <(find "$RUN_ROOT" -type f -name 'epoch030_metrics.json' | sort)
  else
    echo "RUN_ROOT_MISSING $RUN_ROOT"
  fi

  echo "=== ${EXPERIMENT_ID}: STDOUT TAIL ==="
  if [ -f "$STDOUT" ]; then tail -n 140 "$STDOUT"; else echo "STDOUT_MISSING $STDOUT"; fi
  echo "=== ${EXPERIMENT_ID}: STDERR TAIL ==="
  if [ -f "$STDERR" ]; then tail -n 140 "$STDERR"; else echo "STDERR_MISSING $STDERR"; fi
done

echo "=== SOURCE INTEGRITY NOW ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python - <<'PY'
import json
from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity
print(json.dumps(capture_source_integrity("DL01"), indent=2, sort_keys=True))
PY

echo "ID31_PROGRESS_SNAPSHOT_COMPLETE"
