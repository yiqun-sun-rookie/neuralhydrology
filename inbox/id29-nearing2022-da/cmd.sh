#!/bin/bash
# ID29 seq=59: submit the 43 remaining released-code training coordinates as two throttled arrays.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_training_array.slurm"
TIME_BATCH_REL=src/29_nearing2022_da_ar/registry/time_split_remaining_training_batch.txt
BASIN_BATCH_REL=src/29_nearing2022_da_ar/registry/basin_split_training_batch.txt
TIME_BATCH="$ROOT/$TIME_BATCH_REL"
BASIN_BATCH="$ROOT/$BASIN_BATCH_REL"

echo "=== PREFLIGHT ==="
test -f "$SCRIPT"
test "$(grep -cv '^[[:space:]]*$' "$TIME_BATCH")" -eq 23
test "$(grep -cv '^[[:space:]]*$' "$BASIN_BATCH")" -eq 20
sha256sum "$SCRIPT" "$TIME_BATCH" "$BASIN_BATCH"
python - "$ROOT" "$TIME_BATCH" "$BASIN_BATCH" <<'PY'
from pathlib import Path
import sys
from neuralhydrology.utils.config import Config

root = Path(sys.argv[1])
configs = []
for batch_name in sys.argv[2:]:
    configs.extend(line.strip() for line in Path(batch_name).read_text().splitlines() if line.strip())
assert len(configs) == 43
assert len(set(configs)) == 43
experiment_names = []
for relative in configs:
    cfg = Config(root / relative)
    assert cfg.epochs == 30
    assert str(cfg.run_dir).startswith('closure_20260810')
    experiment_names.append(cfg.experiment_name)
assert len(set(experiment_names)) == 43
print(f'config_contract=PASS count={len(configs)} unique_experiments={len(set(experiment_names))}')
PY

if squeue -h -u "$USER" -n N22-time,N22-basin | grep -q .; then
  echo "Refusing duplicate submission: an N22-time or N22-basin array already exists" >&2
  squeue -u "$USER" -n N22-time,N22-basin
  exit 3
fi

echo "=== SUBMIT ==="
TIME_JOB=$(sbatch --parsable --job-name=N22-time --array=0-22%3 \
  --export=ALL,BATCH_FILE_REL="$TIME_BATCH_REL" "$SCRIPT")
BASIN_JOB=$(sbatch --parsable --job-name=N22-basin --array=0-19%2 \
  --export=ALL,BATCH_FILE_REL="$BASIN_BATCH_REL" "$SCRIPT")
echo "time_job_id=$TIME_JOB tasks=23 max_concurrent=3"
echo "basin_job_id=$BASIN_JOB tasks=20 max_concurrent=2"
squeue -j "$TIME_JOB,$BASIN_JOB" -o '%.18i %.18j %.2t %.10M %.6D %R'
